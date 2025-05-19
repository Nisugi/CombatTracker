=begin
  CombatTracker_Parser.lic

        author: Nisugi
  contributors: Nisugi
          game: Gemstone
          tags: hunting, combat, tracking
       version: 0.1

  Change Log:
  v0.1
    - Alpha release
=end

module CombatTracker
  module Parser
    # ---- helpers -------------------------------------------------------
    # Regular expression to match a target link in the text.
    TARGET_LINK = %r{<a exist="(?<id>\d+)" noun="(?<noun>[^"]+)">(?<name>[^<]+)</a>}i.freeze

    # Extracts the target link information from the given text.
    #
    # @param text [String] the text containing the target link.
    # @return [Hash, nil] a hash with keys :id, :noun, and :name if a match is found, otherwise nil.
    # @example
    #   extract_link('<a exist="123" noun="monster">ugly goblin</a>')
    #   # => { id: 123, noun: "goblin", name: "ugly goblin" }
    def self.extract_link(text)
      m = TARGET_LINK.match(text) or return
      { id: m[:id].to_i, noun: m[:noun], name: m[:name] }
    end

    # ---- definitions ---------------------------------------------------
    # Struct definitions for various combat-related entities.
    AttackDef     = Struct.new(:name, :patterns)
    FlareDef      = Struct.new(:name, :patterns, :damaging)
    LodgedDef     = Struct.new(:type, :patterns)
    OutcomeDef    = Struct.new(:type, :patterns)
    ResolutionDef = Struct.new(:type, :patterns)
    StatusDef     = Struct.new(:type, :patterns)

    ATTACK_DEFS = [
      AttackDef.new(:attack, [/You(?: take aim and)? swing .+? at (?<target>[^!]+)!/].freeze),
      AttackDef.new(:barrage, [/Nocking another arrow to your bowstring, you swiftly draw back and loose again!/].freeze),
      AttackDef.new(:companion, [
        /(?<companion>.+?) pounces on (?<target>[^,]+), knocking the .+? painfully to the ground!/,
        /The (?<companion>.+?) takes the opportunity to slash .+? claws at the (?<target>.+?) \w+!/,
        /(?<companion>.+?) charges forward and slashes .+? claws at (?<target>.+?) faster than .+? can react!/
      ].freeze),
      AttackDef.new(:cripple, [/You reverse your grip on your .+? and dart toward (?<target>.+?) at an angle!/].freeze),
      AttackDef.new(:fire, [/You(?: take aim and)? fire .+? at (?<target>[^!]+)!/].freeze),
      AttackDef.new(:flurry, [
        /Flowing with deadly grace, you smoothly reverse the direction of your blades and slash again!/,
        /With fluid motion, you guide your flashing blades, slicing toward (?<target>.+?) at the apex of their deadly arc!/
      ].freeze),
      AttackDef.new(:grapple, [/You(?: make a precise)? attempt to grapple (?<target>[^!]+)!/].freeze),
      AttackDef.new(:jab, [/You(?: make a precise)? attempt to jab (?<target>[^!]+)!/].freeze),
      AttackDef.new(:punch, [/You(?: make a precise)? attempt to punch (?<target>[^!]+)!/].freeze),
      AttackDef.new(:kick, [/You(?: make a precise)? attempt to kick (?<target>[^!]+)!/].freeze),
      AttackDef.new(:natures_fury, [/The surroundings advance upon (?<target>.+?) with relentless fury!/].freeze),
      AttackDef.new(:spikethorn, [/Dozens of long thorns suddenly grow out from the ground underneath (?<target>[^!]+)!/].freeze),
      AttackDef.new(:sunburst, [/The dazzling solar blaze flashes before (?<target>[^!]+)!/].freeze),
      AttackDef.new(:tangleweed, [
        /The (?<weed>.+?) lashes out violently at (?<target>[^,]+), dragging .+? to the ground!/,
        /The (?<weed>.+?) lashes out at (?<target>[^,]+), wraps itself around .+? body and entangles .+? on the ground\./
      ].freeze),
      AttackDef.new(:twinhammer, [/You raise your hands high, lace them together and bring them crashing down towards (?<target>[^!]+)!/].freeze),
      AttackDef.new(:volley, [
        /An arrow finds its mark!  (?<target>.+?) is hit!/,
        /An arrow pierces (?<target>[^!]+)!/,
        /An arrow skewers (?<target>[^!]+)!/,
        /(?<target>.+?) is struck by a falling arrow!/,
        /(?<target>.+?) is transfixed by an arrow's descent!/
      ].freeze),
      AttackDef.new(:wblade, [
        /You turn, blade spinning in your hand toward (?<target>[^!]+)!/,
        /You angle your blade at (?<target>.+?) in a crosswise slash!/,
        /In a fluid whirl, you sweep your blade at (?<target>[^!]+)!/,
        /Your blade licks out at (?<target>.+?) in a blurred arc!/
      ].freeze),
    ].freeze

    FLARE_DEFS = [
      FlareDef.new(:acid, [
        /\*\* Your .+? releases? a spray of acid! \*\*/,
        /\*\* Your .+? releases? a spray of acid at (?<target>.+?)! \*\*/
      ].freeze, true),
      FlareDef.new(:acuity, [/Your .+? glows intensely with a verdant light!/].freeze, false),
      FlareDef.new(:air, [/\*\* Your .+? unleashes a blast of air! \*\*/].freeze, true),
      FlareDef.new(:air_flourish, [/\*\* A fierce whirlwind erupts around .+?, encircling (?<target>.+?) in a suffocating cyclone! \*\*/].freeze, true),
      FlareDef.new(:arcane_reflex, [/Vital energy infuses you, hastening your arcane reflexes!/].freeze, false),
      FlareDef.new(:blink, [/Your .+? suddenly lights up with hundreds of tiny blue sparks!/].freeze, false),
      FlareDef.new(:blessings_flourish, [
        /\*\* A crackling wave arcs across your body, striking (?<target>.+?) with lightning speed!  A spiritual resonance warms your core, lending you renewed strength! \*\*/,
        /\*\* Shimmering arcs of lightning stream from your hands, colliding with (?<target>.+?) in a rapid burst!  A stirring force ignites within you, augmenting your spirit! \*\*/,
        /\*\* Sparkling tendrils of energy weave around your limbs, shocking (?<target>.+?) in a bright flare!  The pulse leaves you feeling spiritually emboldened! \*\*/,
        /\*\* A faint hum courses through you as arcs of electricity coil around your arms, jolting (?<target>.+?) in a vivid burst!  The current resonates with your spirit, boosting your energy! \*\*/,
        /\*\* You feel a tingling surge channel through your arms, blasting (?<target>.+?) with crackling electricity!  A reassuring feeling of mental acuity settles over you! \*\*/,
        /\*\* Jagged sparks dance along your open palms, lashing out at (?<target>.+?) in a crackling surge!  Your resolve feels bolstered as the energy courses through you! \*\*/,
        /\*\* An electrified aura coalesces around you, crackling outward to shock (?<target>[^!]+)!  The charge resonates with your spirit, heightening your prowess! \*\*/,
        /\*\* Threads of charged light spiral around your arms, striking (?<target>.+?) with a pulsing shock!  A resonant force ripples through you, amplifying your spirit! \*\*/,
        /\*\* Sparks of crackling energy race along your fingertips, shocking (?<target>.+?) with a brilliant flash!  A surge of spiritual power rushes through your veins! \*\*/,
        /\*\* A crackling wave arcs across your body, striking (?<target>.+?) with lightning speed!  A spiritual resonance warms your core, lending you renewed strength! \*\*/
      ].freeze, true),
      FlareDef.new(:breeze, [
        /(?<target>.+?) is buffeted by a burst of wind and pushed back!/,
        /(?<target>.+?) is buffeted by a sudden gust of wind!/,
        /A gust of wind shoves (?<target>.+?) back!/
      ].freeze, false),
      FlareDef.new(:briar, [/Vines of vicious briars whip out from your [^,]+, raking the \w+ with its thorns\.  The \w+ looks slightly ill as the glistening emerald coating from each briar works itself under its skin\./].freeze, true),
      FlareDef.new(:chameleon_shroud, [/A tenebrous shroud stitches itself into existence around you as you gracefully retreat into the shadows!/].freeze, false),
      FlareDef.new(:cold, [/Your .+? glows intensely with a cold blue light!/].freeze, true),
      FlareDef.new(:cold_gef, [/\*\* A vortex of razor-sharp ice gusts from .+? and coalesces around (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:concussive_blows, [/\*\* Your blow slams the (?<target>.+?) with concussive force! \*\*/].freeze, true),
      FlareDef.new(:disintegration, [/\*\* Your .+? releases a shimmering beam of disintegration! \*\*/].freeze, true),
      FlareDef.new(:disruption, [/\*\* Your .+? releases a quivering wave of disruption! \*\*/].freeze, true),
      FlareDef.new(:earth_flourish, [/\*\* Chunks of earth violently orbit .+?, pelting (?<target>.+?) with heavy debris and stone! \*\*/].freeze, true),
      FlareDef.new(:earth_gef, [/\*\* A violent explosion of frenetic energy rumbles from .+? and pummels (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:energy, [/\*\* A beam of .+? energy emits from the tip of your .+? and collides with (?<target>.+?\<\/a\>) .+?! \*\*/].freeze, true),
      FlareDef.new(:ensorcell, [/\*\* Necrotic energy from your .+? overflows into you! \*\*/].freeze, false),
      FlareDef.new(:fire, [/\*\* Your .+? flares with a burst of flame! \*\*/].freeze, true),
      FlareDef.new(:fire_flourish, [/\*\* A blazing inferno erupts around .+?, engulfing (?<target>.+?) and scorching everything in its wake! \*\*/].freeze, true),
      FlareDef.new(:fire_gef, [/\*\* Burning orbs of pure flame burst from .+? and engulf (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:firewheel, [/\*\* Your .+? emits a fist-sized ball of lightning-suffused flames! \*\*/].freeze, true),
      FlareDef.new(:ghezyte, [/\*\* Cords of plasma-veined grey mist seep from your .+? and entangle (?<target>[^,]+), causing .+? to tremble violently! \*\*/].freeze, false),
      FlareDef.new(:grapple, [/\*\* Your .+? releases a twisted tendril of force! \*\*/].freeze, true),
      FlareDef.new(:guiding_light, [/\*\* Your .+? sprays with a burst of plasma energy! \*\*/].freeze, true),
      FlareDef.new(:impact, [/\*\* Your .+? release a blast of vibrating energy at the (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:lightning, [/\*\* Your .+? emits a searing bolt of lightning! \*\*/].freeze, true),
      FlareDef.new(:lightning_gef, [/\*\* A vicious torrent of crackling lightning surges from .+? and strikes (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:magma, [/\*\* Your .+? expel a glob of molten magma at the (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:mana, [/You feel \d+ mana surge into you!/].freeze, false),
      FlareDef.new(:natures_decay, [
        /Soot brown specks of leaf mold trail in the wake of (?<target>.+?) movements, distorted by a murky haze\./,
        /The earthy, sweet aroma clinging to (?<target>.+?) grows more pervasive\./,
        /An earthy, sweet armoa clings to (?<target>.+?) in a murky haze\./,
        /An earthy, sweet aroma clings to (?<target>.+?) in a murky haze, accompanied by soot brown specks of leaf mold\./,
      ].freeze, false),
      FlareDef.new(:necromancy_flourish, [/\*\* A sickly green aura radiates from .+? and seeps into (?<target>.+?) wounds! \*\*/].freeze, true),
      FlareDef.new(:parasite, [/A slender .+? and black tendril lashes out from .+? and slashes (?<target>.+?) .+?!/].freeze, true),
      FlareDef.new(:physical_prowess, [/The vitality of nature bestows you with a burst of strength!/].freeze, false),
      FlareDef.new(:plasma, [/\*\* Your .+? pulses with a burst of plasma energy! \*\*/].freeze, true),
      FlareDef.new(:psychic_assault, [/\*\* Your .+? unleashes a blast of psychic energy at the (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:religion_flourish, [/\*\* Divine flames kindle around .+?, leaping forth to engulf (?<target>.+?) in a sacred inferno! \*\*/].freeze, true),
      FlareDef.new(:rusalkan, [/Succumbing to the force of the tidal wave, (?<target>.+?) is thrown to the ground\./].freeze, false),
      FlareDef.new(:somnis, [/\*\* For a split second, the striations of your .+? expand into a sinuous pearlescent mist that rushes towards the (?<target>[^,]+), enveloping .+? entirely and causing .+? to collapse, fast asleep! \*\*/].freeze, false),
      FlareDef.new(:sprite, [/\*\* The .+? sprite on your shoulder sends forth a cylindrical, .+? blast of magic at (?<target>.+?\<\/a\>) .+?! \*\*/].freeze, true),
      FlareDef.new(:steam, [
        /\*\* Your .+? erupts with a plume of steam! \*\*/,
        /\*\* Your .+? erupt with a plume of steam at the (?<target>[^!]+)! \*\*/
      ].freeze, true),
      FlareDef.new(:summining_flourish, [/\*\* A radiant mist surrounds .+?, unfurling into a whip of plasma that wreathes (?<target>.+?) in its sizzling embrace! \*\*/].freeze, true),
      FlareDef.new(:tailwind, [
        /A favorable tailwind springs up behind you\./,
        /You shift position, taking advantage of a favorable tailwind\./,
        /The wind turns in your favor\./
      ].freeze, false),
      FlareDef.new(:telepathy_flourish, [/\*\* Rippling and half-seen, strands of psychic power unravel from .+? to strike at (?<target>.+?)! \*\*/].freeze, true),
      FlareDef.new(:terror, [/\*\* A wave of wicked power surges forth from your .+? and fills (?<target>.+?) with terror, .+? form trembling with unmitigated fear! \*\*/].freeze, false),
      FlareDef.new(:unbalance, [/\*\* Your .+? unleashes an invisible burst of force! \*\*/].freeze, true),
      FlareDef.new(:vacuum, [/\*\* As you hit, the edge of your .+? seems to fold inward upon itself drawing everything it touches along with it! \*\*/].freeze, true),
      FlareDef.new(:valence, [/\*\* A coil of spectral .+? energy bursts out of thin air and strikes (?<target>[^!]+)! \*\*/].freeze, true),
      FlareDef.new(:wall_of_thorns, [/One of the vines surrounding you lashes out at the (?<target>[^,]+), scraping a thorn across .+? body!  .+? flinches slightly./], false),
      FlareDef.new(:water, [/\*\* Your .+? shoot a blast of water! \*\*/].freeze, true),
      FlareDef.new(:water_flourish, [/\*\* A watery deluge erupts violently around .+?, crushing (?<target>.+?) with relentless force! **/].freeze, true),
    ].freeze

    OUTCOME_DEFS = [
      OutcomeDef.new(:miss, [
        /A clean miss./,
        /A close miss./,
        /Nowhere close!/
      ].freeze),
      OutcomeDef.new(:evade, [
        /By amazing chance, (?<target>.+?) evades the .+?!/,
        /Lying flat on .+? back, (?<target>.+?) leans to one side and dodges the .+?!/,
        /Nearly insensible, (?<target>.+?) desperately evades the .+?!/,
        /Rolling hurriedly, (?<target>.+?) blocks the .+? with .+?!/,
        /Stupefied, (?<target>.+?) evades the .+? by blind luck!/,
        /Unable to focus clearly, (?<target>.+?) blindly evades the .+?!/,
        /(?<target>.+?) barely dodges the .+?!/,
        /(?<target>.+?) dodges just in the nick of time!/,
        /(?<target>.+?) evades the .+? by a hair!/,
        /(?<target>.+?) evades the .+? by inches!/,
        /(?<target>.+?) evades the .+? with ease!/,
        /(?<target>.+?) flails on the ground but manages to barely dodge the .+?!/,
        /(?<target>.+?) gracefully avoids the .+?!/,
        /(?<target>.+?) moves at the last moment to evade the .+?!/,
        /(?<target>.+?) rolls to one side and evades the .+?!/,
        /(?<target>.+?) skillfully dodges the .+?!/,
        /(?<target>.+?) stumbles dazedly, somehow managing to evade the .+?!/
      ].freeze),
      OutcomeDef.new(:block, [
        /A heavy barrier of stone momentarily forms around (?<target>.+?) and blocks the attack!/,
        /Amazingly, (?<target>.+?) manages to block the .+? with .+?!/,
        /At the last moment, (?<target>.+?) blocks the .+? with .+?!/,
        /Fumbling aimlessly, (?<target>.+?) manages to deflect the .+? with .+?!/,
        /In the nick of time, (?<target>.+?) interposes .+? between .+? and the .+?!/,
        /Lying flat on .+? back, (?<target>.+?) barely deflects the .+? with .+?!/,
        /Nearly insensible, (?<target>.+?) desperately blocks the .+? with .+?!/,
        /Nearly insensible, (?<target>.+?) wildly blocks the .+? with .+?!/,
        /Reeling and staggering, (?<target>.+?) barely blocks the .+? with .+?!/,
        /Stupefied, (?<target>.+?) blocks the .+? by blind luck!/,
        /The thorny barrier surrounding (?<target>.+?) blocks your .+?!/,
        /Unable to focus clearly, (?<target>.+?) blindly blocks the .+?!/,
        /With extreme effort, (?<target>.+?) blocks the .+? with .+?!/,
        /With no room to spare, (?<target>.+?) blocks the .+? with .+?!/,
        /(?<target>.+?) awkwardly scrambles along the ground to avoid the .+?!/,
        /(?<target>.+?) awkwardly scrambles to the right and blocks the .+?!/,
        /(?<target>.+?) barely manages to block the .+? with .+?!/,
        /(?<target>.+?) easily blocks the .+? with .+?!/,
        /(?<target>.+?) flails on the ground but manages to block the .+? with .+?!/,
        /(?<target>.+?) interposes .+? between .+? and the .+?!/,
        /(?<target>.+?) manages to block the .+? with .+?!/,
        /(?<target>.+?) rolls to one side and deflects the .+? with .+?!/,
        /(?<target>.+?) skillfully blocks the .+? with .+?!/,
        /(?<target>.+?) skillfully interposes .+? between .+? and the .+?!/,
        /(?<target>.+?) stumbles dazedly, but manages to block the .+? with .+?!/,
        /(?<target>.+?) stumbles dazedly, somehow managing to block the .+? with .+?!/,
        /(?<target>.+?) tumbles to the side and deflects the .+? with .+?!/
      ].freeze),
      OutcomeDef.new(:parry, [
        /Amazingly, (?<target>.+?) manages to parry the .+? with .+?!/,
        /At the last moment, (?<target>.+?) parries the .+? with .+?!/,
        /Using the bone plates surrounding .+? forearms, (?<target>.+?) parries your .+?!/,
        /With extreme effort, (?<target>.+?) beats back the .+? with .+?!/,
        /With no room to spare, (?<target>.+?) manages to parry the .+? with .+?!/,
        /(?<target>.+?) barely manages to fend off the .+? with .+?!/,
        /(?<target>.+?) flails on the ground but manages to parry the .+? with .+?!/,
        /(?<target>.+?) rolls to one side and parries the .+? with .+?!/,
      ].freeze),
      OutcomeDef.new(:fumble, [/d100 == 1 FUMBLE!/].freeze),
      OutcomeDef.new(:hindrance, [/\[Spell Hindrance for (?<armor>.+?) is (?<hindrance_amount>\d+)% with current Armor Use skill, d100= (?<roll>\d+)\]/].freeze),
      OutcomeDef.new(:confused, [/Something confusing enters your mind at the worst possible moment, and the distraction disrupts your .+?!/].freeze)
    ]

    RESOLUTION_DEFS = [
      ResolutionDef.new(:as_ds, [/AS: (?<AS>[\+\-\d]+) vs DS: (?<DS>[\+\-\d]+) with AvD: (?<AvD>[\+\-\d]+) \+ d\d+ roll: (?<roll>[\+\-\d]+) \= (?<result>[\+\-\d]+)/]).freeze,
      ResolutionDef.new(:cs_td, [
        /CS: (?<CS>[\+\-\d]+) \- TD: (?<TD>[\+\-\d]+) \+ CvA: (?<CvA>[\+\-\d]+) \+ d\d+\: (?<roll>[\+\-\d]+) \=\= (?<result>[\+\-\d]+)/,
        /CS: (?<CS>[\+\-\d]+) \- TD: (?<TD>[\+\-\d]+) \+ CvA: (?<CvA>[\+\-\d]+) \+ d\d+\: (?<roll>[\+\-\d]+) \+ Bonus: (?<bonus>[\+\-\d]+) \=\= (?<result>[\+\-\d]+)/
      ]).freeze,
      ResolutionDef.new(:smr, [
        /\[SMR Result: (?<result>\d+) \(Open d100: (?<roll>[\+\-\d]+), Bonus: (?<bonus>[\-\+\d]+)\)\]/,
        /\[SMR Result: (?<result>\d+) \(Open d100: (?<roll>[\+\-\d]+)\)\]/
      ]).freeze
    ].freeze

    STATUS_DEFS = [
      StatusDef.new(:stunned, [/The (?<target>.+?) is stunned!/].freeze),
      StatusDef.new(:prone, [
        /It is knocked to the ground!/,
        /(?<target>.+?) is knocked to the ground!/
      ].freeze),
      StatusDef.new(:immobilized, [/(?<target>.+?) form is entangled in an unseen force that restricts .+? movement\./].freeze),
      StatusDef.new(:blind, [/You blinded (?<target>[^!]+)!/].freeze)
    ].freeze

    # Lookup tables for different combat patterns.
    ATTACK_LOOKUP     = ATTACK_DEFS.flat_map     { |d| d.patterns.map { |rx| [rx, d.name] } }.freeze
    FLARE_LOOKUP      = FLARE_DEFS.flat_map      { |d| d.patterns.map { |rx| [rx, d.name, d.damaging] } }.freeze
    RESOLUTION_LOOKUP = RESOLUTION_DEFS.flat_map { |d| d.patterns.map { |rx| [rx, d.type] } }.freeze
    OUTCOME_LOOKUP    = OUTCOME_DEFS.flat_map    { |d| d.patterns.map { |rx| [rx, d.type] } }.freeze
    STATUS_LOOKUP     = STATUS_DEFS.flat_map     { |d| d.patterns.map { |rx| [rx, d.type] } }.freeze

    # Regular expressions to detect various combat actions.
    ATTACK_DETECTOR     = Regexp.union(ATTACK_LOOKUP.map(&:first)).freeze
    FLARE_DETECTOR      = Regexp.union(FLARE_LOOKUP.map(&:first)).freeze
    OUTCOME_DETECTOR    = Regexp.union(OUTCOME_LOOKUP.map(&:first)).freeze
    RESOLUTION_DETECTOR = Regexp.union(RESOLUTION_LOOKUP.map(&:first)).freeze
    STATUS_DETECTOR     = Regexp.union(STATUS_LOOKUP.map(&:first)).freeze

    # Regular expression definitions for lodged attacks.
    LODGED_DEFS = Regexp.union(
      /The .+? breaks into tiny fragments./,
      /The .+? passes straight through (?<target>.+?)<\/popBold> (?<location>.+?) and trails ethereal wisps behind it as it makes its way into the distance\./,
      /The .+? sails through (?<target>.+?) and off into the distance\./,
      /The .+? sticks in (?<target>.+?)'s (?<location>.+?)!/,
      /The .+? streaks off into the distance!/,
      /The .+? streaks into (?<target>.+?)'s (?<location>.+?) and off into the distance\./
    ).freeze
    # The arrow sticks in a heavily armored battle mastodon's abdomen!

    module_function

    # Parses an attack line and extracts relevant information.
    #
    # @param line [String] the line containing the attack information.
    # @return [Hash, nil] a hash with keys :name, :target (if present), and :raw if a match is found, otherwise nil.
    # @example
    #   parse_attack("You swing a sword at an ugly goblin!")
    #   # => { name: "goblin", target: { id: 123456, noun: "goblin", name: "ugly goblin" }, raw: "The goblin attacks with a sword!" }
    def parse_attack(line)
      return unless ATTACK_DETECTOR.match?(line)
      ATTACK_LOOKUP.each do |rx, name|
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

    # Parses a flare line and extracts relevant information.
    #
    # @param line [String] the line containing the flare information.
    # @return [Hash, nil] a hash with keys :name, :damaging, :target (if present), and :raw if a match is found, otherwise nil.
    # @example
    #   parse_flare("A bright flare explodes!")
    #   # => { name: "flare", damaging: true, raw: "A bright flare explodes!" }
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

    # Parses a lodged line and extracts the location of the lodged target.
    #
    # @param line [String] the line containing the lodged information.
    # @return [String, nil] the location of the lodged target if a match is found, otherwise nil.
    # @example
    #   parse_lodged("The arrow sticks in the goblin's arm!")
    #   # => "arm"
    def parse_lodged(line)
      LODGED_DEFS.match(line)
      Regexp.last_match(:location)
    end

    # Parses a resolution line and extracts relevant information.
    #
    # @param line [String] the line containing the resolution information.
    # @return [Hash, nil] a hash with keys :type and :data if a match is found, otherwise nil.
    # @example
    #   parse_resolution("The attack was resolved successfully.")
    #   # => { type: "as_ds", data: { AS: 12 DS: 34 vs AvD: 56 + D100: 78 == 109 } }
    def parse_resolution(line)
      return unless RESOLUTION_DETECTOR.match?(line)
      RESOLUTION_LOOKUP.each do |rx, type|
        return { type:, data: rx.match(line).named_captures.transform_keys(&:to_sym) } if rx.match?(line)
      end
    end

    # Parses an outcome line and extracts the outcome type.
    #
    # @param line [String] the line containing the outcome information.
    # @return [String, nil] the outcome type if a match is found, otherwise nil.
    # @example
    #   parse_outcome("The goblin dodges the attack.")
    #   # => "evade"
    def parse_outcome(line)
      return unless OUTCOME_DETECTOR.match?(line)
      OUTCOME_LOOKUP.each { |rx, type| return type if rx.match?(line)}
    end

    # Parses a status line and extracts the status type.
    #
    # @param line [String] the line containing the status information.
    # @return [String, nil] the status type if a match is found, otherwise nil.
    # @example
    #   parse_status("The goblin is stunned!")
    #   # => "stunned"
    def parse_status(line)
      return unless STATUS_DETECTOR.match?(line)
      STATUS_LOOKUP.each { |rx, type| return type if rx.match?(line) }
    end
  end
end
