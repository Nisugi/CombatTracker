require 'sequel'

# unless Script.exists?("combattracker_parser.rb")
#   puts("CombatTracker requires the script combattracker_parser.rb.")
#   puts("Please download it and try again.")
#   puts(";repository download combattracker_parser")
#   exit
# end
Script.run("ctlib.rb")
Script.run("ctparser.rb")
Script.run("ctprocessor.rb")
Script.run("ctreporter.rb")

module CombatTracker
  DB.load_schema!
  DBSeeder.seed!
  Flusher.start_background!

  DOWNSTREAM_HOOK_ID = 'CombatTracker::downstream'
  PROCESS_QUEUE = Queue.new
  @buffer = []

  class << self
    attr_reader :buffer
  end

  segment_buffer = proc do |server_string|
    CombatTracker.buffer << server_string
    if server_string =~ /<prompt time="\d+">/
      PROCESS_QUEUE << CombatTracker.buffer.shift(CombatTracker.buffer.size)
    end
    server_string
  end
  DownstreamHook.add(DOWNSTREAM_HOOK_ID, segment_buffer)

  before_dying do
    Flusher.flush!
    DownstreamHook.remove(DOWNSTREAM_HOOK_ID)
    DB.conn.disconnect
  end

  loop { Processor.process(PROCESS_QUEUE.pop) }
end