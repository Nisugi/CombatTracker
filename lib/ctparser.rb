# QUIET
module CombatTracker
  module Parser
    TARGET_LINK = %r{<a exist="(?<id>\d+)" noun="(?<noun>[^"]+)">(?<name>[^<]+)</a>}i.freeze
    SPELL_GESTURE_PATTERN = %r{You gesture at (?<target>.+?)\.}.freeze
    CHILD_SPAWN_FLARES = %w[BLINK].freeze

    AttackDef         = Struct.new(:name, :patterns)
    FlareDef          = Struct.new(:name, :patterns, :damaging, :aoe)
    OutcomeDef        = Struct.new(:type, :patterns)
    ResolutionDef     = Struct.new(:type, :patterns)
    SequenceDef       = Struct.new(:name, :start_patterns, :end_patterns)
    SpellPrepDef      = Struct.new(:name, :patterns)
    StatusDef         = Struct.new(:type, :patterns)

    ATTACK_DEFS = [
      AttackDef.new(:attack, [/You(?<aimed> take aim and)? swing .+? at (?<target>[^!]+)!/].freeze),
      AttackDef.new(:balefire, [/You hurl a ball of greenish-black flame at (?<target>[^!]+)!/].freeze),
      AttackDef.new(:barrage, [/Nocking another arrow to your bowstring, you swiftly draw back and loose again!/].freeze),
      AttackDef.new(:cold_snap, [/An airy mist rolls into the area, carrying a harsh chill with it./].freeze),
      AttackDef.new(:companion, [
        /(?<companion>.+?) pounces on (?<target>[^,]+), knocking the .+? painfully to the ground!/,
        /The (?<companion>.+?) takes the opportunity to slash .+? claws at the (?<target>.+?) \w+!/,
        /(?<companion>.+?) charges forward and slashes .+? claws at (?<target>.+?) faster than .+? can react!/
      ].freeze),
      AttackDef.new(:cripple, [/You reverse your grip on your .+? and dart toward (?<target>.+?) at an angle!/].freeze),
      AttackDef.new(:divine_fury, [/A shadowy figure briefly materializes behind (?<target>[^,]+), and a silent scream courses over .+? visage./].freeze),
      AttackDef.new(:earthen_fury, [
        /Fiery debris explodes from the ground beneath (?<target>[^!]+)!/,
        /Craggy debris explodes from the ground beneath (?<target>[^!]+)!/,
        /The earth cracks beneath (?<target>[^,]+), releasing a column of frigid air!/,
        /Icy stalagmites burst from the ground beneath (?<target>[^!]+)!/
      ].freeze),
      AttackDef.new(:fire, [/You(?<aimed> take aim and)? fire .+? at (?<target>[^!]+)!/].freeze),
      AttackDef.new(:flurry, [
        /Flowing with deadly grace, you smoothly reverse the direction of your blades and slash again!/,
        /With fluid motion, you guide your flashing blades, slicing toward (?<target>.+?) at the apex of their deadly arc!/
      ].freeze),
      AttackDef.new(:grapple, [/You(?: make a precise)? attempt to grapple (?<target>[^!]+)!/].freeze),
      AttackDef.new(:jab, [/You(?: make a precise)? attempt to jab (?<target>[^!]+)!/].freeze),
      AttackDef.new(:punch, [/You(?: make a precise)? attempt to punch (?<target>[^!]+)!/].freeze),
      AttackDef.new(:kick, [/You(?: make a precise)? attempt to kick (?<target>[^!]+)!/].freeze),
      AttackDef.new(:natures_fury, [/The surroundings advance upon (?<target>.+?) with relentless fury!/].freeze),
      AttackDef.new(:searing_light, [/The radiant burst of light engulfs (?<target>[^!]+)!/].freeze),
      AttackDef.new(:spikethorn, [/Dozens of long thorns suddenly grow out from the ground underneath (?<target>[^!]+)!/].freeze),
      AttackDef.new(:stone_fist, [/The ground beneath you rumbles, then erupts in a shower of rubble that coalesces in to a large hand with slender fingers in mid-air./].freeze),
      AttackDef.new(:sunburst, [/The dazzling solar blaze flashes before (?<target>[^!]+)!/].freeze),
      AttackDef.new(:tangleweed, [
        /The (?<weed>.+?) lashes out violently at (?<target>[^,]+), dragging .+? to the ground!/,
        /The (?<weed>.+?) lashes out at (?<target>[^,]+), wraps itself around .+? body and entangles .+? on the ground\./
      ].freeze),
      AttackDef.new(:tonis_bolt, [/You unleash a bolt of churning air at (?<target>[^!]+)!/].freeze),
      AttackDef.new(:twinhammer, [/You raise your hands high, lace them together and bring them crashing down towards (?<target>[^!]+)!/].freeze),
      AttackDef.new(:unbalance, [/Bands of spectral mist ripple and surge beneath (?<target>[^!]+)!/].freeze),
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
      AttackDef.new(:web, [/Cloudy wisps swirl about (?<target>.+?)\./].freeze),
    ].freeze

    DAMAGE_DEFS = [
      /\.\.\. and hit for (?<damage>\d+) points? of damage!/,
      /\.\.\. (?<damage>\d+) points? of damage!/,
      /Consumed by the hallowed flames, (?<target>.+?) is ravaged for (?<damage>\d+) points? of damage!/,
      /Wisps of black smoke swirl around (?<target>.+?) and it bursts into flame causing (?<damage>\d+) points? of damage!/
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
      FlareDef.new(:blink, [/Your .+? suddenly lights up with hundreds of tiny blue sparks!/].freeze, true, false),
      FlareDef.new(:blessings_flourish, [
        /\*\* Needles of electric light spark from your fingertips, dancing towards (?<target>[^!]+)!  Your mind clears as a wave of energy washes over you! \*\*/,
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
      FlareDef.new(:dispel, [/\*\* Your .+? glows brightly for a moment, consuming the magical energies around (?<target>[^!]+)! \*\*/].freeze, true, false),
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
      FlareDef.new(:holy_water, [/\*\* Your .+? sprays forth a shower of pure water! \*\*/].freeze, true, false),
      FlareDef.new(:hurl_boulder, [/You hurl a large boulder at (?<target>[^!]+)!/].freeze, true, false),
      FlareDef.new(:immolation, [/You bring a hand up to your lips and form a sign with your fingers as you whisper a quiet invocation for Immolation\.\.\./].freeze, true, false),
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
      FlareDef.new(:sigil_dispel, [/\*\* Tendrils of .+? lash out from your .+? toward (?<target>.+?) and cage .+? within bands of concentric geometry that constrict as one, shattering upon impact! \*\*/].freeze, true, false),
      FlareDef.new(:sigil_cast, [/\*\* Numerous sigils along your .+? abruptly flare to brilliance!  .+? surges from each, twining into an echo of your last spell\.\.\. \*\*/].freeze, true, false),
      FlareDef.new(:slashing_strikes, [/\*\* Your .+? finds its mark, slicing deep into (?<target>.+?)<popBold\/> (?<location>.+?)! \*\*/].freeze, true),
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

    LODGED_DEFS = [
      /The .+? breaks into tiny fragments./,
      /The .+? passes straight through (?<target>.+?)<\/popBold> (?<location>.+?) and trails ethereal wisps behind it as it makes its way into the distance\./,
      /The .+? sails through (?<target>.+?) and off into the distance\./,
      /The .+? sticks in (?<target>.+?)'s (?<location>[^!]+)!/,
      /The .+? streaks off into the distance!/,
      /The .+? streaks into (?<target>.+?)'s (?<location>.+?) and off into the distance\./
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
        /(?<target>.+?) dodges out of the way!/,
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
    ].freeze

    RESOLUTION_DEFS = [
      ResolutionDef.new(:as_ds, [/AS: (?<AS>[\+\-\d]+) vs DS: (?<DS>[\+\-\d]+) with AvD: (?<AvD>[\+\-\d]+) \+ d\d+ roll: (?<roll>[\+\-\d]+) \= (?<result>[\+\-\d]+)/]).freeze,
      ResolutionDef.new(:cs_td, [
                          /CS: (?<CS>[\+\-\d]+) \- TD: (?<TD>[\+\-\d]+) \+ CvA: (?<CvA>[\+\-\d]+) \+ d\d+\: (?<roll>[\+\-\d]+) \=\= (?<result>[\+\-\d]+)/,
                          /CS: (?<CS>[\+\-\d]+) \- TD: (?<TD>[\+\-\d]+) \+ CvA: (?<CvA>[\+\-\d]+) \+ d\d+\: (?<roll>[\+\-\d]+) \+ Bonus: (?<bonus>[\+\-\d]+) \=\= (?<result>[\+\-\d]+)/
                        ]).freeze,
      ResolutionDef.new(:uaf_udf, [/UAF: (?<uaf>\d+) vs UDF: (?<udf>\d+) \= (?<total>[\.\d]+) \* MM: (?<mm>\d+) \+ d\d+: (?<roll>\d+) \= (?<result>\d+)/]).freeze,
      ResolutionDef.new(:smr, [
                          /\[SMR result: (?<result>\d+) \(Open d100: (?<roll>[\+\-\d]+), Bonus: (?<bonus>[\-\+\d]+)\)\]/,
                          /\[SMR result: (?<result>\d+) \(Open d100: (?<roll>[\+\-\d]+)\)\]/
                        ]).freeze
    ].freeze

    SEQUENCE_DEFS = [
      # SequenceDef.new(:barrage, [/Drawing several .+? from your .+?, you grip them loosely between your fingers in preparation for a rapid barrage\./].freeze, [
      #  /Upon firing your last .+?, you release a measured breath and lower your .+?\./,
      #  /Distracted, you hesitate, and your assault is broken.  You give your blades a quick, sweeping flick of annoyance as you lower them\./].freeze),
      SequenceDef.new(:divine_fury, [
        /An agonized, bitter moan echoes through the area from an unseen source, and a dark emerald radiance ripples through the air around you\. The power of Luukos has answered your prayer\./,
        /An ivory light blossoms into existence around you\./,
        /You sense the power of Onar near at hand\./,
        /You begin to hum very softly, harmonizing your notes with those of the greater harmony in the background\./,
        /Summoned by your connection to Voln, the shadowy form of a knight in black chainmail appears beside you, and a cold, grim confidence settles over you\.  You sense that the knight is a manifestation of your own will, and you know that, despite her immaterial appearance, the knight's fire-enveloped blade is fully capable of cleaving through any foe\./,
        /Luminescent golden roses sprout from the ground in a wide ring around you, twisting and twining about as they grow. The power of Voaris has answered your prayer\./,
        /A shimmer in the air precedes the materialization of a pillar of swirling, blue-green water as tall as a giantman not far away from you\. From somewhere in the center of the pillar comes a haunting, wordless threnody\. The power of Niima has answered your prayer\./,
        /The light scents of wildflowers grow stronger as insubstantial brown vines, thick and broad, coil out of the ground around you\. Many of the vines sport large, colorful blossoms\./,
        /Ethereal shadowy black roses sprout from the ground in a wide ring around you, twisting and twining about as they grow\. The power of Laethe has answered your prayer\./,
        /Silvery light briefly glimmers over everything that surrounds you, and a wave of carefully controlled anger that is not your own emotion tunes your pulse to a low, steady thrumming\. You are little more than a channel for the source of the emotion that stares around through your eyes\. The power of the Huntress has answered your prayer\./,
        /As the scent of blossoming lilies fills your senses, a light green glow forms around you and coalesces into living jungle vines that twine over your shoulders and down your arms\. They rest as lightly as a second skin, feeling almost like another part of your body\. The power of Aeia has answered your prayer\./,
        /Chaotic visions and marvelous images flicker around you as the outside world slips farther and farther away from your awareness\. What does it matter, anyway, when you are so close to .+?\. The power of Zelia has answered your prayer\./,
        /From the corner of your eye, you glimpse slight motion\. Although you still can perceive sound, no sounds seem important when compared to the silence at the center of your being\. The power of Gosaena has answered your prayer\./,
        /From within the dark well of bloodlust, you thrill with berserker's ecstasy as you feel the power of V'tull respond to your prayer\. The weapon you need to satisfy your bloodlust materializes before you \-\- a jet black scimitar that hangs in midair and responds to your pure will\./,
        /Visible only at the corner of your vision, you glimpse a pair of dark amber eyes watching from the shadows, and a low, deliberate growl seethes slowly through the air from no discernable source\. The power of Sheru has answered you\./,
        /Tendrils of seeping black mist materialize at a safe distance away from you\. A great awareness of their incredibly lethal power presses into your mind as the tendrils begin to shift and coil about in search of prey\. The power of Marlu has answered your prayer\./,
        /The touch of the ethereal hand against your throat grows colder, and the sensation shifts to encircle your neck like a collar\. Before this manifestation of divine will, you are helpless, and you are helpless as well as the very air around you solidifies into a barbed whip, coiling and shifting restlessly\. The power of Mularos has answered your prayer\./,
        /Your vision splits and twins \-\- with one sight, you see the world around you, and, with the other, you see a wide, barren plain stretching away beneath a midnight sky. The silhouetted forms of pure black unicorns run soundlessly toward you across the dreaming plain\. The power of Ronan has answered your prayer\./,
        /Midnight black flames, sparkling and shimmering like the darkest diamonds ever mined, rise from the ground in a wide circle around you\. You feel the deadly heat, but your skin remains dry beneath it\./,
        /As the wind continues to whip about, the world seems to slow down around you, and you are aware of a spiritual presence nearby, although you cannot manage to catch more than a fleeting golden blur in your vision. The power of Tonis has answered your prayer\./,
        /A faint pink tinge settles over all that you can see, and the scents of blooming wildflowers fill your senses as a light breeze stirs the air around you\. The power of Oleani has answered your prayer\./,
        /As divine wisdom illuminates all things around you, you gain a greater understanding of the frail, tenuous nature of existence and the beauty within that fragility\. The power of Lumnis has answered your prayer\./,
        /It begins to snow \-\- small, white, faintly glowing snowflakes that appear immediately overhead and drift delicately down to dissolve as soon as they strike the ground\. Several strike your skin, and, instead of melting, they only deepen the icy chill that resides within your marrow\. The power of Lorminstra has answered your prayer\./,
        /The ground shivers and trembles restlessly underfoot, and you sense incredible power and strength focusing upon your surroundings\. The power of Koar has answered your prayer\./,
        /Iridescent lights begin to swirl around you, each as brilliant as the finest paints an artist could buy \-\- malachite, lapis, ruby, saffron, umber, orchid, and a thousand other shades, as if you were wrapped in the center of a rainbow\. The power of Jastev has answered your prayer\./,
        /As the ground trembles, you know that the power of Imaera has answered your prayer, and you sense the forms of animal spirits running past unseen\./,
        /The reddish haze shifts and solidifies into the image of a short, stocky, copper-skinned man bending over an anvil\. He pays no attention to you or to anything around you, but you know that the power of Eonak has answered your prayer\./,
        /The sound of laughter and music dances through the air, and, from the corner of your eye, you glimpse the forms of bright-garbed harlequins turning somersaults and tossing juggling balls back and forth \-\- but it is impossible to catch even one jester with a straight-on glance, for the celebratory spirits fade into memory as soon as you spy them\. The power of Cholen has answered your prayer\./,
        /A deafening thunderclap splits the air! Rather than fading away, the sound's echoes grow, and they gather into a rhythmic, crashing pulse like the sound of storm-tossed waves breaking on a desolate shore\. The power of Charl has answered your prayer\./,
        /The prickling sensation increases, and shadows flit across your vision in a web-like pattern, taking on strange shapes before dissolving into the light\.  The power of Arachne has answered your prayer\./
      ].freeze, [
        /As your connection to Aeia lessens, the jungle vines dissolve back into light green radiance, and the radiance seeps softly into your skin\./,
        /Your connection to V'tull lessens, causing the searing bloodlust to vanish instantly away from you\. The scimitar is gone, the haze of berserking hunger has left you, and you feel drained and tired\./,
        /The singing from the watery pillar begins to fade as your connection to Niima lessens\. The pillar thins, then suddenly drops with a great splash! You are utterly drenched in water\./,
        /The ivory light around you fades and glimmers out, and the strength and control of your movements lessens along with your connection to Leya\./,
        /As it reaches the end of its flight, the bone-shafted crossbow bolt disintegrates into unrecognizable dust\./,
        /You feel the kiss of benediction once more upon your brow, and then your connection to Voaris lessens\. One of the glowing golden roses lights with scarlet flame, and the fire spreads rapidly down the vine until every rose is burning\. The flames consume the roses swiftly and without smoke, until, in less than a second, the roses are gone entirely\./,
        /As your connection to Tilamaire lessens, you lose track of the greater harmony within all things, and, regretfully, you bring your song to a close\./,
        /You feel the kiss of benediction once more upon your brow, and then your connection to Laethe lessens\. The shadowy black roses dissolve into tendrils of black, rose-scented smoke that dissipate rapidly\./,
        /Suddenly, the important insights slip away, leaving you drained and exhausted as you plummet back to a more mundane state of mind. Your throat and sides are slightly sore, and your cheeks are wet with tears\. Your connection to Zelia has lessened\./,
        /You realize that you had ceased to hear the sound of your own heartbeat only when you become aware of it again, and other sounds filter back into your awareness as well. Warmth returns to your body as your connection to Gosaena lessens\./,
        /You feel your connection to Voln lessen\.  The shadowy knight turns to you, salutes you gravely, and vanishes entirely from existence\./,
        /As the spiritual peace slowly leaves you, the vines shimmer and vanish one by one, and the scent of wildflowers drifts away as your connection to Kuon lessens\./,
        /Your connection to Sheru lessens, and the murky shadows brought by your appeal fade away, yet the feeling of being watched does not. On any night, in any dream or nightmare, those amber eyes will follow you endlessly\.\.\. but such is the prize and the price of your devotion\./,
        /The tendrils of black mist dissolve back into nothingness as your connection to Marlu lessens\./,
        /As your connection to Mularos lessens, the cold, invisible collar locked about your throat fades into a compassionate caress, and a similar caress traces its way across the side of your cheek\. Beneath that gentle touch, the wounds upon your face heal immediately\. The ethereal barbed whip twitches one last time before dissolving back into air\./,
        /A spectral howl echoes through the air, resonant with pain and anguish\. Your skin prickles again as your connection to Luukos lessens\./,
        /Your connection to Eorgina lessens, and the black flames instantly vanish, leaving you stranded and bereft of the presence of the Arkati's power\./,
        /As your connection to the Huntress lessens, the foreign anger that lent you strength passes from your body as well, and your heartbeat returns to its regular pace\./,
        /You glimpse the golden blur one last time, but then you lose track of it entirely as your connection to Tonis lessens\. The wind's force lessens as well, and then the air falls still\./,
        /You lose sight of the dream unicorns and the barren plain upon which they run as your connection to Ronan lessens\. The waking world seems brighter again as the sense of dreamlike lassitude leaves you\./,
        /The scent of wildflowers fades away, and the world returns to its natural hues\. Your connection to Oleani has lessened\./,
        /As your connection to Lumnis lessens, the world of divine insight slips away from you, destroying the subtle understanding that you so briefly managed to grasp\./,
        /As your connection to Lorminstra lessens, the snowflakes stop falling, and the few that still cling to you melt away\. The icy cold gradually lifts from your body\./,
        /Your connection to Koar lessens, and the divine light fades around you\. The ground shudders one last time before falling still\./,
        /The iridescent lights surrounding you pop like soap bubbles, one by one, until the last one bursts in a small flare of starry radiance and is gone\. Your connection to Jastev lessens\./,
        /You sense the last of the spirit animals running away unseen, and the aroma of forest loam fades as your connection to Imaera lessens\./,
        /The ruddy haze near you dissipates, and the sound of the forging hammer dies away\. As the forge-fire's heat leaves your skin, your connection to Eonak lessens\./,
        /Your connection to Cholen lessens\. The airy, brisk trill of a well-played fife and a quick cymbal crash heralds the departure of the spirit jesters\./,
        /A final rumble of thunder rolls through the area, and, as its last echoes fade away, your skin ceases to tingle as your connection to Charl lessens\./,
        /The prickling sensation fades as your connection to Arachne lessens\./
      ].freeze),
      SequenceDef.new(:earthen_fury, [
        /The ground beneath (?<target>.+?) begins to boil violently!/,
        /The ground beneath (?<target>.+?) suddenly frosts and rumbles violently!/,
        /The ground beneath (?<target>.+?) boils with renewed vigor!/,
        /The ground beneath (?<target>.+?) rumbles with renewed vigor!/
      ].freeze, [/The ground beneath (?<target>.+?) suddenly calms\./].freeze),
      SequenceDef.new(:flurry, [
        /You rotate your wrist, your .+? executing a casual spin to establish your flow as you advance upon (?<target>.+?)!/,
        /You rotate your wrists, your .+? and .+? executing a casual spin to establish your flow as you advance upon (?<target>[^!]+)!/
      ].freeze, [
        /The mesmerizing sway of body and blade glides to its inevitable end with one final twirl of your .+?\./,
        /Distracted, you hesitate, and your assault is broken.  You give your blades a quick, sweeping flick of annoyance as you lower them\./
      ].freeze),
      SequenceDef.new(:mstrike, [
        # You concentrate intently, focusing all your energies.
        /With great haste, you let loose a volley of shots!/,
        /With instinctive motions, you weave to and fro striking with deliberate and unrelenting fury!/,
        /You explode into a fury of strikes and ripostes, moving with a singular purpose and will!/
      ].freeze, [
        /Your series of strikes and ripostes leaves you winded and out of position./,
        /Your series of strikes and ripostes leaves you off-balance and out of position./,
        /Your series of rapid shots and maneuvers leaves you off-balance and out of position./
      ].freeze),
      SequenceDef.new(:natures_fury, [
        /You close your eyes in a moment of intense concentration, channeling the pure natural power of your surroundings\.  As you continue to gather the energy, a low thrumming resounds through the area\.  Suddenly, a multitude of sharp pieces of debris splinter off from underfoot, savagely assailing everything around you!/,
        /You close your eyes in a moment of intense concentration, channeling the pure natural power of your surroundings\.  As you continue to gather the energy, a low thrumming resounds through the area\.  Suddenly, dense bunches of leafy ferns with large spiny stems sprout forth from the loamy soil, savagely assailing everything around you!/,
        /You close your eyes in a moment of intense concentration, channeling the pure natural power of your surroundings\.  As you continue to gather the energy, a low thrumming resounds through the area\.  Suddenly, masses of large needled branches jab outward from the surrounding trees, savagely assailing everything around you!/,
        /You close your eyes in a moment of intense concentration, channeling the pure natural power of your surroundings\.  As you continue to gather the energy, a low thrumming resounds through the area\.  Suddenly, enormously overgrown dirge-vaon vines spring up from the cultivated surroundings and flail about chaotically, savagely assailing everything around you!/
      ].freeze, [/As swiftly as the chaos came to be, it recedes again into the surroundings\./].freeze),
      SequenceDef.new(:searing_light, [/When the ball glows so brightly that it begins to singe your skin, you unleash the radiance before you and it instantaneously spreads throughout the entire area!/].freeze, [/\bnone\b/].freeze),
      SequenceDef.new(:volley, [/Raising your .+? high, you loose .+? as fast as you can, filling the sky with a volley of deadly projectiles!/].freeze, [/The air clears as the deadly volley of arrows abates\./].freeze)
    ].freeze

    SPELL_DATA = {
      # 100s
      unbalance: { display_name: 'Unbalance', needs_prep: false, damaging: true },
      fire_spirit: { display_name: 'Fire Spirit', needs_prep: false, damaging: true },
      # 300s
      bane: { display_name: 'Bane', needs_prep: true, damaging: true },
      ethereal_censer: { display_name: 'Ethereal Censer', needs_prep: true, damaging: true },
      # 400s
      elemental_blast: { display_name: 'Elemental Blast', needs_prep: true, damaging: true },
      elemental_wave: { display_name: 'Elemental Wave', needs_prep: true, damaging: false },
      elemental_strike: { display_name: 'Elemental Strike', needs_prep: true, damaging: true },
      major_elemental_wave: { display_name: 'Major Elemental Wave', needs_prep: true, damaging: false },
      # 500s
      sleep: { display_name: 'Sleep', needs_prep: true, damaging: false },
      chromatic_circle: { display_name: 'Chromatic Circle', needs_prep: true, damaging: true },
      slow: { display_name: 'Slow', needs_prep: true, damaging: false },
      hand_of_tonis: { display_name: 'Hand of Tonis', needs_prep: true, damaging: true },
      mana_leech: { display_name: 'Mana Leech', needs_prep: true, damaging: false },
      cone_of_elements: { display_name: 'Cone of Elements', needs_prep: true, damaging: true },
      meteor_swarm: { display_name: 'Meteor Swarm', needs_prep: true, damaging: true },
      # 900s
      minor_shock: { display_name: 'Minor Shock', needs_prep: true, damaging: true },
      minor_water: { display_name: 'Minor Water', needs_prep: true, damaging: true },
      minor_acid: { display_name: 'Minor Acid', needs_prep: true, damaging: true },
      minor_fire: { display_name: 'Minor Fire', needs_prep: true, damaging: true },
      major_cold: { display_name: 'Major Cold', needs_prep: true, damaging: true },
      major_fire: { display_name: 'Major Fire', needs_prep: true, damaging: true },
      major_shock: { display_name: 'Major Shock', needs_prep: true, damaging: true },
      weapon_fire: { display_name: 'Weapon Fire', needs_prep: true, damaging: false },
      # 700s
      blood_burst: { display_name: 'Blood Burst', needs_prep: true, damaging: true },
      corrupt_essence: { display_name: 'Corrupt Essence', needs_prep: true, damaging: false },
      disintegrate: { display_name: 'Disintegrate', needs_prep: true, damaging: true },
      tenebrous_tether: { display_name: 'Tenebrous Tether', needs_prep: true, damaging: false }, # ??
      limb_disruption: { display_name: 'Limb Disruption', needs_prep: true, damaging: true },
      pain: { display_name: 'Pain', needs_prep: true, damaging: true },
      curse: { display_name: 'Curse', needs_prep: true, damaging: true },
      pestilence: { display_name: 'Pestilence', needs_prep: true, damaging: true },
      evil_eye: { display_name: 'Evil Eye', needs_prep: true, damaging: true },
      dark_catalyst: { display_name: 'Dark Catalyst', needs_prep: true, damaging: true },
    }.freeze

    SPELL_PREP_PATTERNS = [
      /A haze of black mist gathers around you as you prepare (?<spell_name>.+?)\.\.\./,
      /Ephemeral twists of silver-hazed mist wreathe your forearms as you murmur a serene phrase for (?<spell_name>.+?)\.\.\./,
      /Mirage-like distortions surround you as you prepare the (?<spell_name>.+?) spell\.\.\./,
      /With the whispered words of (?<spell_name>.+?), you summon forth the rot and ruin of nature to devour your enemies/,
      /You bring a hand up to your lips and form a sign with your fingers as you whisper a quiet invocation for (?<spell_name>.+?)\.\.\./,
      /You chant a reverent litany, clasping your hands while focusing upon the (?<spell_name>.+?) spell\.\.\./,
      /You trace a simple rune while intoning the mystical phrase for (?<spell_name>.+?)\.\.\./,
      /You trace an intricate sign that contorts in the air while forcefully invoking (?<spell_name>.+?)\.\.\./,
      /You utter a light chant and raise your hands, beckoning the lesser spirits to aid you with the (?<spell_name>.+?) spell\.\.\./

    ].freeze

    STATUS_DEFS = [
      StatusDef.new(:blind, [/You blinded (?<target>[^!]+)!/].freeze),
      StatusDef.new(:immobilized, [/(?<target>.+?) form is entangled in an unseen force that restricts .+? movement\./].freeze),
      StatusDef.new(:prone, [
        /It is knocked to the ground!/,
        /(?<target>.+?) is knocked to the ground!/
      ].freeze),
      StatusDef.new(:stunned, [/The (?<target>.+?) is stunned!/].freeze),
      StatusDef.new(:sunburst, [/(?<target>.+?) reels and stumbles under the intense flare!/].freeze),
      StatusDef.new(:webbed, [/(?<target>.+?) becomes ensnared in thick strands of webbing!/].freeze)
    ].freeze

    # Lookup tables for different combat patterns.
    SEQUENCE_START_LOOKUP  = SEQUENCE_DEFS.flat_map    { |d| d.start_patterns.map { |rx| [rx, d.name,] } }
    SEQUENCE_END_LOOKUP    = SEQUENCE_DEFS.flat_map    { |d| d.end_patterns.map { |rx| [rx, d.name] } }
    ATTACK_LOOKUP     = ATTACK_DEFS.flat_map     { |d| d.patterns.map { |rx| [rx, d.name] } }.freeze
    FLARE_LOOKUP      = FLARE_DEFS.flat_map      { |d| d.patterns.map { |rx| [rx, d.name, d.damaging, d.aoe] } }.freeze
    RESOLUTION_LOOKUP = RESOLUTION_DEFS.flat_map { |d| d.patterns.map { |rx| [rx, d.type] } }.freeze
    OUTCOME_LOOKUP    = OUTCOME_DEFS.flat_map    { |d| d.patterns.map { |rx| [rx, d.type] } }.freeze
    STATUS_LOOKUP     = STATUS_DEFS.flat_map     { |d| d.patterns.map { |rx| [rx, d.type] } }.freeze
    SPELL_NAME_LOOKUP = SPELL_DATA.transform_values { |v| v[:display_name] }.invert.freeze

    # Regular expressions to detect various combat actions.
    SEQUENCE_START_DETECTOR  = Regexp.union(SEQUENCE_START_LOOKUP.map(&:first)).freeze
    SEQUENCE_END_DETECTOR    = Regexp.union(SEQUENCE_END_LOOKUP.map(&:first)).freeze
    ATTACK_DETECTOR     = Regexp.union(ATTACK_LOOKUP.map(&:first)).freeze
    DAMAGE_DETECTOR     = Regexp.union(DAMAGE_DEFS).freeze
    FLARE_DETECTOR      = Regexp.union(FLARE_LOOKUP.map(&:first)).freeze
    LODGED_DETECTOR     = Regexp.union(LODGED_DEFS).freeze
    OUTCOME_DETECTOR    = Regexp.union(OUTCOME_LOOKUP.map(&:first)).freeze
    RESOLUTION_DETECTOR = Regexp.union(RESOLUTION_LOOKUP.map(&:first)).freeze
    SPELL_PREP_DETECTOR = Regexp.union(SPELL_PREP_PATTERNS).freeze
    STATUS_DETECTOR     = Regexp.union(STATUS_LOOKUP.map(&:first)).freeze

    SEQUENCE_SPELLS = SEQUENCE_DEFS.map(&:name).map(&:to_sym).freeze
  end
end
