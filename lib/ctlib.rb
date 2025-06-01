# QUIET
module CombatTracker
  module Config
    class << self
      attr_accessor :session_timeout, :flush_interval, :max_cache_rows, :db_path
    end

    self.session_timeout = 60       # seconds of inactivity before a new session
    self.flush_interval  = 300      # seconds between background DB flushes
    self.max_cache_rows  = 10_000   # early flush threshold
    self.db_path         = File.join(DATA_DIR, XMLData.game, Char.name, 'combat.db')
  end

  module Log
    LEVELS = %i[VERBOSE DEBUG INFO WARN ERROR].freeze
    @level = :INFO

    class << self
      def level
        @level
      end

      def level=(lvl)
        if LEVELS.include?(lvl)
          @level = lvl
        else
          warn "[CB WARN ] Unknown log level #{lvl.inspect}; keeping #{@level}"
        end
      end

      def log(level, ctx, msg)
        return if LEVELS.index(level) < LEVELS.index(@level)
        timestamp = Time.now.strftime('%H:%M:%S')
        respond "[#{timestamp}] [CB #{level.to_s.upcase.ljust(5)}] [#{ctx}] #{msg}"
      end
    end
  end

  module DB
    extend self

    def conn
      @conn ||= Sequel.sqlite(
        Config.db_path,
        timeout: 10_000,
        journal_mode: :wal,
        synchronous: :normal
      )
    end

    def load_schema!
      path = File.expand_path('db_schema.sql', DATA_DIR)
      return unless conn.tables.empty?
      conn.run(File.read(path))
      Log.log(:info, :DB, "Schema initialized -> #{path}")
      conn.run 'PRAGMA foreign_keys = ON'
    end
  end

  module DBSeeder
    def self.seed!
      conn = DB.conn

      Parser::SEQUENCE_DEFS.each do |seq_def|
        conn[:sequence_types]
          .insert_conflict(target: :name, do_nothing: true)
          .insert(name: seq_def.name.to_s.upcase)
      end

      Parser::ATTACK_DEFS.each do |atk_def|
        conn[:attack_types]
          .insert_conflict(target: :name, do_nothing: true)
          .insert(name: atk_def.name.to_s.upcase)
      end

      Parser::SPELL_DATA.each do |spell_sym, spell_info|
        if spell_info[:needs_prep]
          conn[:attack_types]
            .insert_conflict(target: :name, do_nothing: true)
            .insert(name: spell_sym.to_s.upcase)
        end
      end

      Parser::FLARE_DEFS.each do |fl_def|
        conn[:flare_types]
          .insert_conflict(target: :name, do_nothing: true)
          .insert(name: fl_def.name.to_s.upcase)
      end

      Parser::OUTCOME_DEFS.each do |out_def|
        conn[:outcome_types]
          .insert_conflict(target: :name, do_nothing: true)
          .insert(name: out_def.type.to_s.upcase)
      end

      Parser::RESOLUTION_DEFS.each do |res_def|
        conn[:resolution_types]
          .insert_conflict(target: :name, do_nothing: true)
          .insert(name: res_def.type.to_s.upcase)
      end

      Parser::STATUS_DEFS.each do |st_def|
        conn[:status_types]
          .insert_conflict(target: :name, do_nothing: true)
          .insert(name: st_def.type.to_s.upcase)
      end

      Log.log(:info, "DBSEED", "Seeded lookup tables from Parser defs")
    end
  end

  module DebugInsert
    def self.insert(table, row)
      Log.log(:DEBUG, "DB-INS", "-> #{table}: #{row.inspect}") unless table == :resolution_components
      DB.conn[table].insert(row)
    rescue SQLite3::ConstraintException => e
      Log.log(:ERROR, "DB-INS", "FAILED #{table}: #{e.class}: #{e.message}")
      fk_defs = DB.conn["PRAGMA foreign_key_list(#{table})"].all
      Log.log(:ERROR, "DB-INS", "FK definitions for #{table}: #{fk_defs.inspect}")
      violations = DB.conn['PRAGMA foreign_key_check'].all
      Log.log(:ERROR, "DB-INS", "Current FK violations: #{violations.inspect}")
      raise
    end
  end

  module Lookup
    def self.id(table, name)
      DB.conn[table].first(name: name.to_s.upcase)&.fetch(:id) || raise("Unknown #{table}: #{name}")
    end

    def self.label(table, id)
      DB.conn[table].first(id: id)&.fetch(:name) || raise("Unknown ID #{id} in #{table}")
    end
  end

  module Session
    extend self

    @id = nil
    @seq = 0
    @last_seen = nil

    def current_id = ensure_session!

    def next_sequence = ensure_session! && (@seq += 1)

    private

    def ensure_session!
      now  = Time.now
      char = defined?(Char) ? Char.name : 'Unknown'

      if @id && !DB.conn[:combat_sessions].where(id: @id).count.positive?
        Log.log(:INFO, "SESSION", "Session #{@id} not found in database, resetting state")
        @id = nil
        @seq = 0
      end

      if @id.nil? || now - (@last_seen || 0) > Config.session_timeout
        DB.conn[:combat_sessions].where(id: @id).update(ended_at: now) if @id
        @id = DB.conn[:combat_sessions].insert(character_name: char, started_at: now, last_event_at: now)
        raise "Failed to create session" unless DB.conn[:combat_sessions].where(id: @id).count > 0
        @seq = 0
      else
        DB.conn[:combat_sessions].where(id: @id).update(last_event_at: now)
      end

      @last_seen = now
      @id
    end
  end

  module Store
    CACHE = Hash.new { |h, k| h[k] = [] }
    MUTEX = Mutex.new

    module_function

    def push(table, row)
      MUTEX.synchronize { CACHE[table] << row }
      Flusher.flush! if CACHE[table].size >= Config.max_cache_rows
    end
  end

  module Flusher
    TABLES = %i[
      creature_instances attack_events attack_resolutions resolution_components
      status_events flare_events damage_components
    ].freeze

    module_function

    def flush!
      batches = nil
      Store::MUTEX.synchronize { batches = Store::CACHE.transform_values(&:dup) }
      return if batches.values.all?(&:empty?)

      DB.conn.transaction do
        TABLES.each do |t|
          rows = batches[t] or next
          rows = dedup_creatures(rows) if t == :creature_instances
          DB.conn[t].multi_insert(rows, slice: 1_000) unless rows.empty?
        end
      end

      Store::MUTEX.synchronize { TABLES.each { |tbl| Store::CACHE[tbl].clear } }
    rescue => e
      Log.log(:error, :FLUSH, "flush failed ? #{e.message}")
    end

    def dedup_creatures(rows)
      rows
        .group_by { |r| [r[:session_id], r[:exist_id]] }
        .values
        .map { |grp| grp.max_by { |r| r[:last_seen_at] } }
    end

    def start_background!
      Thread.new do
        loop do
          sleep Config.flush_interval
          flush!
        end
      end
    end
  end

  module Parser
    module_function

    def extract_link(text)
      m = TARGET_LINK.match(text) or return
      { id: m[:id].to_i, noun: m[:noun], name: m[:name] }
    end

    def parse_attack(line)
      return unless ATTACK_DETECTOR.match?(line)
      ATTACK_LOOKUP.each do |rx, name| # Only rx and name now
        if (m = rx.match(line))
          info = { name: name, raw: line.strip }
          if m.names.include?('target')
            raw_t = m[:target]
            info[:target] = extract_link(raw_t) || { id: nil, noun: nil, name: raw_t }
          end
          return info
        end
      end
    end

    def parse_damage(line)
      return unless DAMAGE_DETECTOR.match?(line)
      DAMAGE_DEFS.each do |rx|
        if (m = rx.match(line))
          return m[:damage].to_i
        end
      end
      nil
    end

    def parse_flare(line)
      return unless FLARE_DETECTOR.match?(line)
      FLARE_LOOKUP.each do |rx, name, damaging|
        if (m = rx.match(line))
          info = { name:, damaging:, raw: line.strip }
          if m.names.include?('target')
            info[:target] = extract_link(m[:target]) || { id: nil, noun: nil, name: m[:target] }
          end
          return info
        end
      end
    end

    def parse_lodged(line)
      return unless LODGED_DETECTOR.match?(line)
      LODGED_DEFS.each do |rx|
        if (m = rx.match(line))
          info = { raw: line.strip }
          if m.names.include?('target')
            raw_t = m[:target]
            info[:target] = extract_link(raw_t) || { id: nil, noun: nil, name: raw_t }
          end
          if m.names.include?('location') && (loc = m[:location])
            info[:location] = loc.upcase.strip
          end
          return info
        end
      end
      nil
    end

    def parse_outcome(line)
      return unless OUTCOME_DETECTOR.match?(line)
      OUTCOME_LOOKUP.each { |rx, type| return type if rx.match?(line) }
    end

    def parse_resolution(line)
      return unless RESOLUTION_DETECTOR.match?(line)
      RESOLUTION_LOOKUP.each do |rx, type|
        return { type:, data: rx.match(line).named_captures.transform_keys(&:to_sym) } if rx.match?(line)
      end
    end

    def parse_sequence_start(line)
      return unless SEQUENCE_START_DETECTOR.match?(line)
      SEQUENCE_START_LOOKUP.each { |rx, type| return type if rx.match?(line) }
    end

    def parse_sequence_end(line)
      return unless SEQUENCE_END_DETECTOR.match?(line)
      SEQUENCE_END_LOOKUP.each { |rx, type| return type if rx.match?(line) }
    end

    def parse_spell_prep(line)
      return unless SPELL_PREP_DETECTOR.match?(line)

      SPELL_PREP_PATTERNS.each do |pattern|
        if (m = pattern.match(line))
          spell_display_name = m[:spell_name]
          spell_sym = SPELL_NAME_LOOKUP[spell_display_name]

          # Only return if this spell needs prep tracking
          if spell_sym && SPELL_DATA[spell_sym][:needs_prep]
            return spell_sym
          end
        end
      end
      nil
    end

    def parse_status(line)
      return unless STATUS_DETECTOR.match?(line)
      STATUS_LOOKUP.each { |rx, type| return type if rx.match?(line) }
    end
  end
end
