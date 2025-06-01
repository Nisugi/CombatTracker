# QUIET
module CombatTracker
  class Reporter
    #-----------------------------
    # ATTACK DEBUGGER
    #-----------------------------
    def self.attack_debug(attack_id)
      attack_id = attack_id.to_i

      # 1. Basic attack info
      attack = DB.conn[:attack_events]
                 .join(:attack_types, id: :attack_type_id)
                 .join(:outcome_types, Sequel[:outcome_types][:id] => Sequel[:attack_events][:outcome_id])
                 .where(Sequel[:attack_events][:id] => attack_id)
                 .select(
                   Sequel[:attack_events][:id],
                   Sequel[:attack_events][:sequence],
                   Sequel[:attack_events][:creature_instance_id],
                   Sequel[:attack_types][:name].as(:attack_type),
                   Sequel[:outcome_types][:name].as(:outcome),
                   Sequel[:attack_events][:occurred_at]
                 )
                 .first

      unless attack
        respond "Attack ID #{attack_id} not found"
        return
      end

      msg = "\n=== ATTACK DEBUG REPORT ##{attack_id} ==="
      msg += "\nType: #{attack[:attack_type]}"
      msg += "\nOutcome: #{attack[:outcome]}"
      msg += "\nSequence: #{attack[:sequence]}"
      msg += "\nOccurred: #{attack[:occurred_at]}"

      # 2. Target creature
      if attack[:creature_instance_id]
        creature = DB.conn[:creature_instances]
                     .where(id: attack[:creature_instance_id])
                     .first
        msg += "\nTarget: #{creature[:display_name]} (#{Lich::Messaging.make_cmd_link("##{creature[:exist_id]}", ";eq CombatTracker::Reporter.creature_debug(#{creature[:exist_id]})")})"

      else
        msg += "\nTarget: NONE"
      end

      # 3. Resolution -- Surely we can clean up this output to show the resolution and in a line and not just list the components
      resolution = DB.conn[:attack_resolutions]
                     .join(:resolution_types, id: :resolution_type)
                     .where(attack_id: attack_id)
                     .select(
                       Sequel[:resolution_types][:name].as(:type),
                       :result_total,
                       :d100_roll
                     )
                     .first

      if resolution
        msg += "\n\nRESOLUTION:"
        msg += "\n  Type: #{resolution[:type]}"
        msg += "\n  Result: #{resolution[:result_total]}"
        msg += "\n  Roll: #{resolution[:d100_roll]}"

        # Resolution components
        components = DB.conn[:resolution_components]
                       .where(resolution_id: DB.conn[:attack_resolutions].where(attack_id: attack_id).get(:id))
                       .select_map([:component_name, :component_value])

        if components.any?
          msg += "\n  Components:"
          components.each do |name, value|
            msg += "\n    #{name}: #{value}"
          end
        end
      else
        msg += "\n\nRESOLUTION: NONE"
      end

      # 4. Damage components
      damages = DB.conn[:damage_components]
                  .where(
                    Sequel.|(
                      { attack_id: attack_id },                              # direct hit
                      { flare_id: DB.conn[:flare_events]
                                    .where(attack_id: attack_id)
                                    .select(:id) }                           # flares fired by this attack
                    )
                  )
                  .order(:id)
                  .all

      if damages.any?
        msg << "\n\nDAMAGE COMPONENTS (#{damages.count}):"
        damages.each_with_index do |d, i|
          msg << "\n  [#{i + 1}] Damage: #{d[:damage]}"
          msg << " (from flare #{Lich::Messaging.make_cmd_link("##{d[:flare_id]}", ";eq CombatTracker::Reporter.flare_debug(#{d[:flare_id]})")})" if d[:flare_id] # <— already there
          if d[:location_id]
            loc = DB.conn[:locations].where(id: d[:location_id]).get(:name)
            crit_type = d[:critical_type] && DB.conn[:critical_types].where(id: d[:critical_type]).get(:name)
            msg << "\n      Crit: #{loc} R#{d[:critical_rank]} #{crit_type}"
            msg << " FATAL" if d[:is_fatal]
          end
        end
      else
        msg << "\n\nDAMAGE COMPONENTS: NONE"
      end

      # 5. Status effects
      statuses = DB.conn[:status_events]
                   .join(:status_types, id: :status_type)
                   .where(applied_by_attack: attack_id)
                   .select_map(Sequel[:status_types][:name])

      if statuses.any?
        msg += "\n\nSTATUS EFFECTS: #{statuses.join(', ')}"
      else
        msg += "\n\nSTATUS EFFECTS: NONE"
      end

      # 6. Flares ─ now fetch child attack via damage_components
      flares = DB.conn[:flare_events]
                 .join(:flare_types, id: :flare_type_id)
                 .where(Sequel[:flare_events][:attack_id] => attack_id)
                 .select(
                   Sequel[:flare_events][:id].as(:flare_id), # ← qualify & alias
                   Sequel[:flare_types][:name].as(:flare_name),
                   Sequel[:flare_events][:child_attack_id]
                 )
                 .all

      if flares.any?
        msg << "\n\nFLARES (#{flares.size}):"
        flares.each do |f|
          msg << "\n  #{f[:flare_name]} (Flare ID #{Lich::Messaging.make_cmd_link("##{f[:flare_id]}", ";eq CombatTracker::Reporter.flare_debug(#{f[:flare_id]})")})"

          child_ids = DB.conn[:damage_components]
                        .where(flare_id: f[:flare_id])
                        .exclude(attack_id: nil)
                        .distinct
                        .select_map(:attack_id)
          child_ids << f[:child_attack_id] if f[:child_attack_id]
          child_ids.uniq!

          next if child_ids.empty?

          # choose the child whose creature matches the parent if possible
          pcid = child_ids.find do |cid|
            DB.conn[:attack_events].where(id: cid)
              .get(:creature_instance_id) ==
              attack[:creature_instance_id]
          end
          pcid ||= child_ids.first

          # build a short summary (atype | outcome | ts)
          child = DB.conn[:attack_events]
                    .join(:attack_types, id: :attack_type_id)
                    .join(:outcome_types,
                          Sequel[:outcome_types][:id] =>
                                                         Sequel[:attack_events][:outcome_id]) # ← fixed join
                    .where(Sequel[:attack_events][:id] => pcid)
                    .select(
                      Sequel[:attack_types][:name].as(:atype),
                      Sequel[:outcome_types][:name].as(:outcome),
                      Sequel[:attack_events][:occurred_at]
                    )
                    .first

          msg << " -> Child Attack " + Lich::Messaging.make_cmd_link("##{pcid}", ";eq CombatTracker::Reporter.attack_debug(#{pcid})")
          msg << " [#{child[:atype]} | #{child[:outcome]} | #{child[:occurred_at]}]"
        end
      else
        msg << "\n\nFLARES: NONE"
      end

      # 7. Sequence info
      if (seq_id = DB.conn[:attack_events].where(id: attack_id).get(:sequence_event_id))
        seq = DB.conn[:sequence_events]
                .join(:sequence_types, id: :sequence_type_id)
                .where(Sequel[:sequence_events][:id] => seq_id)
                .select(
                  Sequel[:sequence_types][:name],
                  :started_at,
                  :ended_at
                )
                .first
        msg += "\n\nSEQUENCE: #{seq[:name]}"
        msg += "\n  Started: #{seq[:started_at]}"
        msg += "\n  Ended: #{seq[:ended_at] || 'ACTIVE'}"

        # ---- NEW: show every attack in this sequence ----
        steps = DB.conn[:attack_events]
                  .join(:attack_types, id: :attack_type_id)
                  .join(:outcome_types,
                        Sequel[:outcome_types][:id] =>
                                                       Sequel[:attack_events][:outcome_id])
                  .where(sequence_event_id: seq_id)
                  .order(:sequence_step)
                  .select(
                    :sequence_step,
                    Sequel[:attack_events][:id].as(:atk_id),
                    Sequel[:attack_types][:name].as(:atype),
                    Sequel[:outcome_types][:name].as(:outcome),
                    Sequel[:attack_events][:occurred_at]
                  )
                  .all

        if steps.any?
          msg << "\n  Steps:"
          steps.each do |s|
            link = Lich::Messaging.make_cmd_link("##{s[:atk_id]}", ";eq CombatTracker::Reporter.attack_debug(#{s[:atk_id]})")
            msg << "\n    [#{s[:sequence_step]}] " \
                   "Attack #{link} - #{s[:atype]} | #{s[:outcome]} | #{s[:occurred_at]}"
          end
        end
      end

      # 8. Raw SQL check for damage
      # raw_damages = DB.conn.fetch("SELECT * FROM damage_components WHERE attack_id = ?", attack_id).all
      # msg += "\n\nRAW DAMAGE QUERY (#{raw_damages.count} rows):"
      # raw_damages.each do |row|
      #  msg += "\n  #{row.inspect}"
      # end

      _respond Lich::Messaging.mono(msg)
    end

    # ----------------------------
    #  FLARE DEBUGGER
    # ----------------------------
    def self.flare_debug(flare_id)
      flare_id = flare_id.to_i
      row = DB.conn[:flare_events]
              .join(:flare_types, id: :flare_type_id)
              .where(Sequel[:flare_events][:id] => flare_id)
              .select(
                Sequel[:flare_events][:id].as(:id),
                Sequel[:flare_types][:name].as(:name),
                :attack_id, :child_attack_id,
                :session_id, :attack_sequence, :flare_sequence
              ).first

      unless row
        respond "Flare ID #{flare_id} not found"
        return
      end

      msg  = "\n=== FLARE DEBUG REPORT ##{flare_id} ==="
      msg << "\nType:   #{row[:name]}"
      msg << "\nFired by Attack:  " \
             "#{Lich::Messaging.make_cmd_link("##{row[:attack_id]}",
                                              ";eq CombatTracker::Reporter.attack_debug(#{row[:attack_id]})")}"
      if row[:child_attack_id]
        msg << "\nSpawned Child:    " \
               "#{Lich::Messaging.make_cmd_link("##{row[:child_attack_id]}",
                                                ";eq CombatTracker::Reporter.attack_debug(#{row[:child_attack_id]})")}"
      else
        msg << "\nSpawned Child:    NONE"
      end

      # damage caused *directly* by the flare
      dmg = DB.conn[:damage_components]
              .where(flare_id: flare_id)
              .all
      if dmg.any?
        msg << "\n\nDAMAGE COMPONENTS (#{dmg.count}):"
        dmg.each_with_index do |d, i|
          msg << "\n  [#{i + 1}] #{d[:damage]} dmg" \
                 "#{d[:location_id] ? " to #{DB.conn[:locations].where(id: d[:location_id]).get(:name)}" : ''}"
        end
      else
        msg << "\n\nDAMAGE COMPONENTS: NONE"
      end

      _respond Lich::Messaging.mono(msg)
    end

    # ----------------------------
    #  CREATURE DEBUGGER  (exist‑ID, not creature_instance_id)
    # ----------------------------
    def self.creature_debug(exist_id)
      exist_id = exist_id.to_i

      # Get the most recent instance of this creature
      creature = DB.conn[:creature_instances]
                   .where(exist_id: exist_id)
                   .order(Sequel.desc(:first_seen_at))
                   .first

      unless creature
        respond "No creature with exist_id #{exist_id} found"
        return
      end

      msg = "\n=== CREATURE DEBUG REPORT (exist #{exist_id}) ==="
      msg += "\nDisplay: #{creature[:display_name]}"
      msg += "\nNoun: #{creature[:noun]}"
      msg += "\nSession: #{creature[:session_id]}"
      msg += "\nFirst/Last seen: #{creature[:first_seen_at]} -> #{creature[:last_seen_at]}"
      msg += "\nKilled at: #{creature[:killed_at] || 'ALIVE'}"

      # Get all attacks against this creature
      attacks = DB.conn[:attack_events]
                  .join(:attack_types, id: :attack_type_id)
                  .where(creature_instance_id: creature[:id])
                  .select(
                    Sequel[:attack_events][:id],
                    Sequel[:attack_types][:name].as(:attack_type),
                    Sequel[:attack_events][:sequence]
                  )
                  .order(:sequence)
                  .all

      # Collect all unique status effects
      status_ids = attacks.map { |a| a[:id] }
      if status_ids.any?
        statuses = DB.conn[:status_events]
                     .join(:status_types, id: :status_type)
                     .where(applied_by_attack: status_ids)
                     .select_map(Sequel[:status_types][:name])
                     .uniq

        msg += "\nStatus Effects: #{statuses.any? ? statuses.join(', ') : 'NONE'}"
      else
        msg += "\nStatus Effects: NONE"
      end

      # Get all damage events
      msg += "\n\nDAMAGE EVENTS:"

      # Direct attack damage
      attack_damages = DB.conn[:damage_components]
                         .join(:attack_events, Sequel[:attack_events][:id] => :attack_id)
                         .join(:attack_types, Sequel[:attack_types][:id] => Sequel[:attack_events][:attack_type_id])
                         .left_join(:locations, Sequel[:locations][:id] => Sequel[:damage_components][:location_id])
                         .left_join(:critical_types, Sequel[:critical_types][:id] => Sequel[:damage_components][:critical_type])
                         .where(Sequel[:attack_events][:creature_instance_id] => creature[:id])
                         .where(Sequel[:damage_components][:flare_id] => nil)
                         .select(
                           Sequel[:damage_components][:damage],
                           Sequel[:damage_components][:critical_rank],
                           Sequel[:locations][:name].as(:location),
                           Sequel[:critical_types][:name].as(:crit_type),
                           Sequel[:damage_components][:is_fatal],
                           Sequel[:attack_types][:name].as(:attack_name),
                           Sequel[:attack_events][:id].as(:attack_id),
                           Sequel[:attack_events][:sequence]
                         )
                         .order(Sequel[:attack_events][:sequence])
                         .all

      # Flare damage - flare_events has creature_instance_id in damage_components
      flare_damages = DB.conn.fetch(<<-SQL, creature[:id]).all
        SELECT#{' '}
          dc.damage,
          dc.critical_rank,
          loc.name as location,
          ct.name as crit_type,
          dc.is_fatal,
          ft.name as flare_name,
          ae.id as attack_id,
          ae.sequence,
          fe.id as flare_id
        FROM damage_components dc
        JOIN flare_events fe ON fe.id = dc.flare_id
        JOIN flare_types ft ON ft.id = fe.flare_type_id
        JOIN attack_events ae ON ae.id = fe.attack_id
        LEFT JOIN locations loc ON loc.id = dc.location_id
        LEFT JOIN critical_types ct ON ct.id = dc.critical_type
        WHERE ae.creature_instance_id = ?
        ORDER BY ae.sequence
      SQL

      # Combine and sort all damages by sequence
      all_damages = []

      attack_damages.each do |d|
        dmg_str = "  - #{d[:damage].to_s.rjust(3)} dmg"
        if d[:critical_rank]
          # Get wound rank from CritRanks
          crit_info = CritRanks.fetch(d[:crit_type].downcase.to_sym, d[:location].downcase.gsub(' ', '_').to_sym, d[:critical_rank])
          wound_rank = crit_info[:wound_rank] || d[:critical_rank] # fallback to crit rank if fetch fails

          dmg_str += "  R#{wound_rank} #{d[:crit_type]} wound on #{d[:location]}"
          dmg_str += " [FATAL]" if d[:is_fatal]
        end
        dmg_str += " from #{d[:attack_name]} (#{Lich::Messaging.make_cmd_link("attack ##{d[:attack_id]}", ";eq CombatTracker::Reporter.attack_debug(#{d[:attack_id]})")})"
        all_damages << [d[:sequence], dmg_str]
      end

      flare_damages.each do |d|
        dmg_str = "  - #{d[:damage].to_s.rjust(3)} dmg"
        if d[:critical_rank]
          # Get wound rank from CritRanks
          crit_info = CritRanks.fetch(d[:crit_type].downcase.to_sym, d[:location].downcase.gsub(' ', '_').to_sym, d[:critical_rank])
          wound_rank = crit_info[:wound_rank] || d[:critical_rank] # fallback to crit rank if fetch fails

          dmg_str += " caused R#{wound_rank} #{d[:crit_type]} wound on #{d[:location]}"
          dmg_str += " [FATAL]" if d[:is_fatal]
        end
        dmg_str += " from #{d[:flare_name]} flare (#{Lich::Messaging.make_cmd_link("flare ##{d[:flare_id]}", ";eq CombatTracker::Reporter.flare_debug(#{d[:flare_id]})")})"
        all_damages << [d[:sequence], dmg_str]
      end

      # Sort by sequence and display
      all_damages.sort_by(&:first).each do |_, dmg_str|
        msg += "\n#{dmg_str}"
      end

      if all_damages.empty?
        msg += "\n  NONE"
      end

      # Summary stats
      total_damage = attack_damages.sum { |d| d[:damage] } + flare_damages.sum { |d| d[:damage] }
      msg += "\n\nSUMMARY:"
      msg += "\n  Total attacks received: #{attacks.count}"
      msg += "\n  Total damage taken: #{total_damage}"
      msg += "\n  Attack types: #{attacks.map { |a| a[:attack_type] }.uniq.join(', ')}"

      # Check for any orphaned damage components
      attack_ids = attacks.map { |a| a[:id] }
      if attack_ids.any?
        flare_ids = DB.conn[:flare_events]
                      .where(attack_id: attack_ids)
                      .select_map(:id)

        orphaned = DB.conn[:damage_components]
                     .where(attack_id: attack_ids)
                     .where(flare_id: nil)
                     .exclude(attack_id: attack_ids)
                     .count

        orphaned += DB.conn[:damage_components]
                      .where(flare_id: flare_ids)
                      .exclude(flare_id: flare_ids)
                      .count if flare_ids.any?

        if orphaned > 0
          msg += "\n\nWARNING: #{orphaned} orphaned damage components found!"
        end
      end

      _respond Lich::Messaging.mono(msg)
    end
  end
end
