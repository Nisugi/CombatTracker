# QUIET
module CombatTracker
  module Processor
    module_function

    @pending_child_flares ||= []

    def process(chunk)
      events = parse_events(chunk)
      return if events.empty?
      DB.conn.transaction { events.each { |ev| persist(ev) } }
    end

    def parse_events(lines)
      events = []
      current = nil
      pending = nil

      lines.each do |ln|
        if (sd = Parser.parse_sequence_start(ln))
          target = Parser.extract_link(ln) || {}
          pending = {
            type: :sequence,
            name: sd,
            started_at: Time.now,
            ended_at: nil,
            target: target,
            step: 0
          }

        elsif (spell_prep = Parser.parse_spell_prep(ln))
          Log.log(:DEBUG, "PARSE", "Found spell prep: #{spell_prep}")
          pending = {
            type: :spell,
            name: spell_prep,
            target: nil,
            started_at: Time.now
          }

        elsif pending && pending[:type] == :spell && (gesture_match = Parser::SPELL_GESTURE_PATTERN.match(ln))
          Log.log(:DEBUG, "PARSE", "Found gesture, pending: #{pending.inspect}")
          target = Parser.extract_link(gesture_match[:target]) || { id: nil, noun: nil, name: gesture_match[:target] }
          pending[:target] = target

        elsif pending && pending[:type] == :sequence && Parser.parse_sequence_end(ln)
          pending[:ended_at] = Time.now
        end

        if (a = Parser.parse_attack(ln))
          if Parser::SEQUENCE_SPELLS.include?(a[:name]) &&
             !(pending && pending[:type] == :sequence && pending[:name] == a[:name])
            next # ignore third‑party sequence attacks
          end
          events << current if current
          current = init_event(a)
          current[:ctx] = :attack

          if pending && a[:name] == pending[:name]
            current[:sequence_event] = pending
            pending[:step] += 1
            current[:sequence_step] = pending[:step]
          elsif pending && pending[:type] == :spell
            current[:target] = pending[:target] if current[:target][:id].nil? && pending[:target]
            pending = nil
          end

        elsif current && (o = Parser.parse_outcome(ln))
          current[:outcome] = o

        elsif pending && pending[:type] == :spell && (r = Parser.parse_resolution(ln))
          Log.log(:DEBUG, "PARSE", "Found resolution for pending spell: #{pending.inspect}")
          # This resolution is for a spell that had prep but no attack line!
          events << current if current
          current = init_event({
            name: pending[:name],
            damaging: true,
            spell: true,
            aoe: false,
            target: pending[:target] || {}
          })
          current[:resolution] = r
          current[:ctx] = :attack
          pending = nil

        elsif pending && pending[:type] == :spell && (d = Parser.parse_damage(ln))
          # Create attack from pending spell
          events << current if current
          current = init_event({
            name: pending[:name],
            damaging: true,
            spell: true,
            aoe: false,
            target: pending[:target] || {}
          })
          current[:damages] << d
          current[:ctx] = :attack
          pending = nil

        elsif current && (r = Parser.parse_resolution(ln))
          if current[:ctx] == :flare && current[:flares].any?
            # Resolution belongs to the flare (will create child attack during persist)
            current[:flares].last[:resolution] = r
          else
            # Normal attack resolution
            current[:resolution] = r
          end
          current[:ctx] = :attack  # Reset context after resolution

        elsif current && (d = Parser.parse_damage(ln))
          if current[:ctx] == :flare && current[:flares].any?
            current[:flares].last[:damages] << d
          else
            current[:damages] << d
          end

        elsif current && (s = Parser.parse_status(ln))
          current[:statuses] << s

        elsif current && (f = Parser.parse_flare(ln))
          current[:flares] << f.merge(target: current[:target], damages: [], crits: [])
          current[:ctx] = :flare

        elsif current && (c = CritRanks.parse(ln.gsub(/<.+?>/, '')).values.first)
          if current[:ctx] == :flare && current[:flares].any?
            current[:flares].last[:crits] << { type: c[:type], location: c[:location], rank: c[:rank], wound_rank: c[:wound_rank], fatal: c[:fatal] }
          else
            current[:crits] << { type: c[:type], location: c[:location], rank: c[:rank], wound_rank: c[:wound_rank], fatal: c[:fatal] }
          end

        elsif current && (l = Parser.parse_lodged(ln))
          current[:lodged] = l
          current[:ctx] = :attack  # Lodged message ends the attack sequence

          # Try to extract target if we don't have one
          if current[:target][:id].nil?
            t = Parser.extract_link(ln) || { id: nil, noun: nil, name: l }
            current[:target] = t if t[:id]
          end

        end
      end
      events << current if current
      events
    end

    def init_event(attack_info)
      {
        name: attack_info[:name],
        target: attack_info[:target] || {},
        resolution: nil,
        damages: [],
        crits: [],
        statuses: [],
        flares: [],
        ctx: :attack,
        sequence_event_id: nil,
        sequence_step: 0
      }
    end

    def persist(ev)
      session_id = Session.current_id
      seq        = Session.next_sequence
      tgt        = ev[:target]
      ci_id      = upsert_creature(session_id, tgt) if tgt[:id]
      now        = Time.now
      outcome_id = (Lookup.id(:outcome_types, ev[:outcome]) rescue 1)

      attrs = {
        session_id: session_id,
        sequence: seq,
        creature_instance_id: ci_id,
        attack_type_id: Lookup.id(:attack_types, ev[:name]),
        outcome_id: outcome_id,
        occurred_at: now
      }

      if ev[:sequence_event]
        se = ev[:sequence_event]
        unless se[:id]
          key = se[:name].to_s.upcase
          se_id = CombatTracker::DebugInsert.insert(:sequence_events, {
            session_id: session_id,
            creature_instance_id: ci_id,
            sequence_type_id: Lookup.id(:sequence_types, key),
            started_at: se[:started_at],
            ended_at: se[:ended_at]
          })
          se[:id] = se_id
        end
        attrs[:sequence_event_id] = se[:id]
        attrs[:sequence_step]     = ev[:sequence_step]

        if se[:ended_at]
          DB.conn[:sequence_events]
            .where(id: se[:id])
            .update(ended_at: se[:ended_at])
        end
      end

      attack_id = DebugInsert.insert(:attack_events, attrs)

      pf = @pending_child_flares.find { |f| f[:creature_instance_id] == ci_id }
      tag_only_pf = pf.nil? && @pending_child_flares.first

      if pf # && flare_spawns_child?(Lookup.label(:flare_types, pf[:flare_type_id])) # exact creature‑match => finalise the link
        DB.conn[:flare_events]
          .where(id: pf[:id], child_attack_id: nil)
          .update(child_attack_id: attack_id)

        @pending_child_flares.delete(pf) # remove only now
        @current_attack_flare_id = pf[:id]

      elsif tag_only_pf # wrong creature ⇒ tag damage but KEEP the flare queued
        @current_attack_flare_id = tag_only_pf[:id]

      else
        @current_attack_flare_id = nil
      end

      @current_attack_flare_id = nil unless pf

      ev[:damages].each_with_index do |damage, i|
        damage_component = {
          attack_id: attack_id,
          damage: damage,
        }
        damage_component[:flare_id] = @current_attack_flare_id if @current_attack_flare_id

        if outcome_id == 1 && (crit = ev[:crits][i])
          damage_component[:location_id]    = Lookup.id(:locations, crit[:location])
          damage_component[:critical_type]  = Lookup.id(:critical_types, crit[:type])
          damage_component[:critical_rank]  = crit[:rank]
          damage_component[:is_fatal]       = crit[:fatal]
          # Creature[ev[:target][:id]].append_injury(crit[:location], crit[:wound_rank]) if crit[:wound_rank] && crit[:wound_rank] > 0
          # puts "Appending injury to Creature: #{ev[:target][:id]} - #{crit[:location]} (#{crit[:wound_rank]}) - attack_id #{attack_id}" if crit[:wound_rank] && crit[:wound_rank] > 0
        else
          if outcome_id == 1 && (ev[:name] != :natures_fury)
            Log.log(:WARN, "CRIT", "No crit message detected for attack #{ev[:name]} (#{attack_id}).")
          end
        end
        CombatTracker::DebugInsert.insert(:damage_components, damage_component)
      end

      persist_statuses(ev[:statuses], attack_id)
      persist_resolution(ev[:resolution], attack_id, seq, session_id) if ev[:resolution]
      persist_flares(ev[:flares], attack_id, seq, session_id, ev[:target][:id]) if ev[:flares].any?
      persist_lodged(ev[:lodged], attack_id, ci_id, now) if ev[:lodged]
    end

    def upsert_creature(session_id, tgt)
      now = Time.now
      Log.log(:DEBUG, "CREATURE", "upsert_creature session_id=#{session_id.inspect}, exist_id=#{tgt[:id]}")
      exists = DB.conn[:combat_sessions].where(id: session_id).count.positive?
      Log.log(:DEBUG, "CREATURE", "  combat_sessions[#{session_id}] exists? #{exists}")
      DB.conn[:creature_instances]
        .insert_conflict(target: %i[session_id exist_id], update: { last_seen_at: now })
        .insert(session_id: session_id, exist_id: tgt[:id], noun: tgt[:noun],
                display_name: tgt[:name], first_seen_at: now, last_seen_at: now)
      DB.conn[:creature_instances].where(session_id:, exist_id: tgt[:id]).get(:id)
    end

    def persist_statuses(sts, atk_id)
      now = Time.now
      sts.each do |st|
        CombatTracker::DebugInsert.insert(:status_events, {
          applied_by_attack: atk_id,
          status_type: Lookup.id(:status_types, st),
          started_at: now,
          ended_at: nil
        })
      end
    end

    def persist_resolution(res, atk_id, seq, session_id)
      type_id = Lookup.id(:resolution_types, res[:type])

      # build the full row with all NOT NULL fields
      row = {
        session_id: session_id,
        attack_id: atk_id,
        sequence: seq,
        resolution_type: type_id,
        result_total: res[:data][:result].to_i,
        d100_roll: res[:data][:roll].to_i,
      }

      # insert and grab its PK
      res_id = CombatTracker::DebugInsert.insert(:attack_resolutions, row)

      # now persist the components as before
      res[:data].each do |k, v|
        next if %i[total roll].include?(k)
        CombatTracker::DebugInsert.insert(:resolution_components, {
          resolution_id: res_id,
          component_name: k.to_s.upcase,
          component_value: v.to_i
        })
      end
    end

    def flare_spawns_child?(flare_name)
      Parser::CHILD_SPAWN_FLARES.include?(flare_name.to_s.upcase)
    end

    def persist_flares(flares, parent_atk_id, parent_seq, session_id, exist_id)
      flares.each_with_index do |fl, i|
        # ─────────────────────────── 1) flare_events row ───────────────────────────
        flare_event_id = CombatTracker::DebugInsert.insert(:flare_events, {
          session_id: session_id,
          attack_id: parent_atk_id,
          attack_sequence: parent_seq,
          flare_sequence: i + 1,
          flare_type_id: Lookup.id(:flare_types, fl[:name]),
          child_attack_id: nil
        })

        ci_id = upsert_creature(session_id, fl[:target])

        if flare_spawns_child?(fl[:name])
          @pending_child_flares << {
            id: flare_event_id,
            creature_instance_id: ci_id,
            parent_attack_id: parent_atk_id
          }
        end

        # ──────────────────────── 3) damage_components rows ──────────────────────
        next unless fl[:damaging]

        fl[:damages].each_with_index do |damage, di|
          dc_row = {
            flare_id: flare_event_id,
            creature_instance_id: ci_id,
            damage: damage
          }

          if (crit = fl[:crits][di])
            dc_row[:location_id]   = Lookup.id(:locations,      crit[:location])
            dc_row[:critical_type] = Lookup.id(:critical_types, crit[:type])
            dc_row[:critical_rank] = crit[:rank]
            dc_row[:is_fatal]      = crit[:fatal]
            # Creature[exist_id].append_injury(crit[:location], crit[:wound_rank]) if crit[:wound_rank] && crit[:wound_rank] > 0
            # puts "Appending injury to Creature: #{exist_id} - #{crit[:location]} (#{crit[:wound_rank]}) - flare_id #{flare_event_id}" if crit[:wound_rank] && crit[:wound_rank] > 0
          end

          CombatTracker::DebugInsert.insert(:damage_components, dc_row)
        end
      end
    end

    def persist_lodged(lodged, atk_id, ci_id, time)
      Log.log(:DEBUG, "LODG", "Lodged is #{lodged}.")

      # nothing to store if no body‑part was mentioned
      return unless lodged && lodged[:location]

      loc_key = lodged[:location].upcase.strip
      loc_id  = Lookup.id(:locations, loc_key) rescue nil
      unless loc_id
        Log.log(:WARN, "LODG",
                "Unknown location '#{loc_key}', attack_id=#{atk_id} – row skipped")
        return
      end

      CombatTracker::DebugInsert.insert(:lodged_events, {
        attack_id: atk_id,
        creature_id: ci_id, # may still be nil if arrow sailed away
        location_id: loc_id,
        lodged_at: time,
        removed_at: nil
      })
    end
  end
end
