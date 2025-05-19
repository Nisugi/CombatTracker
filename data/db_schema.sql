/* =========================================================
   DATABASE:  Gemstone IV Combat Tracker
   ========================================================= */

PRAGMA foreign_keys = ON;   -- must be on for FK enforcement
PRAGMA journal_mode  = WAL; -- already true in your Sequel connect

BEGIN;

/* =========================================================
   1.  REFERENCE / LOOK‑UP TABLES
   ========================================================= */

CREATE TABLE creature_types (
    id     SERIAL  PRIMARY KEY,
    noun   TEXT    UNIQUE NOT NULL,
    notes  TEXT
);

CREATE TABLE attack_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE resolution_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE damage_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE flare_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE status_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE locations (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE critical_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE outcome_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE defense_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

INSERT OR IGNORE INTO locations (id, name) VALUES
  (1, 'ABDOMEN'),
  (2, 'BACK'),
  (3, 'CHEST'),
  (4, 'HEAD'),
  (5, 'LEFT ARM'),
  (6, 'LEFT EYE'),
  (7, 'LEFT FOOT'),
  (8, 'LEFT HAND'),
  (9, 'LEFT LEG'),
  (10, 'NECK'),
  (11, 'NERVES'),
  (12, 'RIGHT ARM'),
  (13, 'RIGHT EYE'),
  (14, 'RIGHT FOOT'),
  (15, 'RIGHT HAND'),
  (16, 'RIGHT LEG');


INSERT OR IGNORE INTO critical_types (id, name) VALUES
  (1, 'ACID'),
  (2, 'COLD'),
  (3, 'CRUSH'),
  (4, 'DISINTEGRATE'),
  (5, 'DISRUPTION'),
  (6, 'FIRE'),
  (7, 'GRAPPLE'),
  (8, 'IMPACT'),
  (9, 'LIGHTNING'),
  (10, 'NON-CORPOREAL'),
  (11, 'PLASMA'),
  (12, 'PUNCTURE'),
  (13, 'SLASH'),
  (14, 'STEAM'),
  (15, 'UCS_GRAPPLE'),
  (16, 'UCS_JAB'),
  (17, 'UCS_KICK'),
  (18, 'UCS_PUNCH'),
  (19, 'UNBALANCE'),
  (20, 'VACUUM');

/* (optional) seed data; keep or delete as you like */
INSERT OR IGNORE INTO outcome_types (id, name) VALUES
  (1,'HIT'),(2,'MISS'),(3,'PARRY'),(4,'BLOCK'),(5,'EVADE'),(6,'FUMBLE')
ON CONFLICT DO NOTHING;

INSERT OR IGNORE INTO defense_types (id, name) VALUES
  (1,'SHIELD_BLOCK'),(2,'WEAPON_PARRY'),(3,'DODGE'),(4,'AUTO_KD')
ON CONFLICT DO NOTHING;


/* =========================================================
   2.  FACT / EVENT TABLES
   ========================================================= */

-- 2‑a  Combat session (one per hunt / log chunk)
CREATE TABLE combat_sessions (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    character_name TEXT NOT NULL,
    started_at     DATETIME NOT NULL,
    last_event_at  DATETIME NOT NULL,   -- 180‑second timeout tracking
    ended_at       DATETIME
);

-- 2‑b  Creature instances (unique within a session)
CREATE TABLE creature_instances (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id    INTEGER NOT NULL REFERENCES combat_sessions(id),
    exist_id      INTEGER NOT NULL,
    noun          TEXT NOT NULL,
    display_name  TEXT NOT NULL,
    first_seen_at DATETIME NOT NULL,
    last_seen_at  DATETIME,
    killed_at     DATETIME,
    killed_by_attack_id INTEGER REFERENCES attack_events(id),
    UNIQUE (session_id, exist_id)
);

-- 2‑c  Attack events
CREATE TABLE attack_events (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id            INTEGER NOT NULL REFERENCES combat_sessions(id),
  sequence              INTEGER NOT NULL,
  creature_instance_id  INTEGER,
  attack_type_id        INTEGER REFERENCES attack_types(id),
  occurred_at           DATETIME NOT NULL,
  outcome_id            INTEGER REFERENCES outcome_types(id),
  is_fatal              BOOLEAN DEFAULT FALSE,
  FOREIGN KEY (creature_instance_id) REFERENCES creature_instances(id) DEFERRABLE INITIALLY DEFERRED
);
-- timeline index: all activity in a hunt
CREATE INDEX idx_attack_session_time ON attack_events(session_id, sequence);
CREATE INDEX idx_attack_events_creature_instance ON attack_events(creature_instance_id);


-- 2‑d  Resolution header (one‑to‑one with attack)
CREATE TABLE attack_resolutions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      INTEGER NOT NULL REFERENCES combat_sessions(id) ON DELETE CASCADE,
    sequence        INTEGER NOT NULL,
    attack_id       INTEGER REFERENCES attack_events(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    resolution_type INTEGER NOT NULL REFERENCES resolution_types(id),
    result_total    INTEGER,               -- nullable for odd rolls
    d100_roll       INTEGER,
    raw_line        TEXT,
    UNIQUE (attack_id)
);
CREATE INDEX idx_resolutions_session_seq ON attack_resolutions(session_id, sequence);

-- 2‑e  Resolution components (flexible key/value)
CREATE TABLE resolution_components (
    resolution_id    INTEGER REFERENCES attack_resolutions(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    session_id       INTEGER NOT NULL REFERENCES combat_sessions(id),
    sequence         INTEGER NOT NULL,
    component_name   TEXT    NOT NULL,
    component_value  INTEGER NOT NULL,
    PRIMARY KEY (resolution_id, component_name)
);
CREATE INDEX idx_components_session_seq ON resolution_components(session_id, sequence);

-- 2‑f  Defense events (optional row per defensive outcome)
CREATE TABLE defense_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    attack_id     INTEGER NOT NULL REFERENCES attack_events(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    defense_type  INTEGER REFERENCES defense_types(id),
    defended_by   TEXT NOT NULL CHECK (defended_by IN ('TARGET','ALLY','ENVIRONMENT')),
    detail        TEXT
);

/*Block defense rows on non-defensive outcomes*/
CREATE TRIGGER defense_outcome_enforce
BEFORE INSERT ON defense_events
FOR EACH ROW
WHEN (
    (SELECT name
        FROM outcome_types
      WHERE id = (
        SELECT outcome_id 
          FROM attack_events 
         WHERE id = NEW.attack_id
      )
    ) NOT IN ('PARRY', 'BLOCK', 'EVADE', 'FUMBLE')
)
BEGIN
  SELECT RAISE(ABORT,
    'Defense row illegal: parent attack is not a defensive outcome');
end;

-- 2‑g  Damage components
CREATE TABLE damage_components (
    id            INTEGER PRIMARY KEY,
    attack_id     INTEGER REFERENCES attack_events(id) ON DELETE CASCADE,
    flare_id      INTEGER REFERENCES flare_events(id),
    location_id   INTEGER REFERENCES locations(id),
    damage        INTEGER,
    critical_type INTEGER REFERENCES critical_types(id),
    critical_rank INTEGER,
    damage_type   INTEGER REFERENCES damage_types(id)
);
CREATE INDEX idx_damage_components_attack ON damage_components(attack_id);
CREATE INDEX idx_damage_components_flare ON damage_components(flare_id);


-- 2‑h  Flare events
CREATE TABLE flare_events (
    id              INTEGER PRIMARY KEY,
    session_id      INTEGER NOT NULL DEFAULT 0,
    attack_sequence INTEGER NOT NULL DEFAULT 0,
    flare_sequence  INTEGER NOT NULL DEFAULT 0,
    flare_type_id   INTEGER REFERENCES flare_types(id),
    attack_id       INTEGER REFERENCES attack_events(id) ON DELETE CASCADE,
    flare_type      INTEGER REFERENCES flare_types(id),
    is_fatal        BOOLEAN DEFAULT FALSE
);
CREATE INDEX idx_flares_session_seq ON flare_events(session_id, attack_sequence);
CREATE INDEX idx_flare_events_attack_id ON flare_events(attack_id);


-- 2‑i  Projectile instances (every lodged arrow / bolt / dagger …)
CREATE TABLE projectiles (
    id              INTEGER PRIMARY KEY,
    attack_id       INTEGER   REFERENCES attack_events(id)        ON DELETE CASCADE,
    creature_id     INTEGER   REFERENCES creature_instances(id),
    location_id     INTEGER REFERENCES locations(id),
    lodged_at       DATETIME,
    removed_at      DATETIME,
    fatal_strike    BOOLEAN  DEFAULT FALSE,
    notes           TEXT
);
CREATE INDEX idx_projectiles_creature_loc ON projectiles(creature_id, location_id);
CREATE INDEX idx_projectiles_attack ON projectiles(attack_id);

-- 2‑j  Status events (stuns, webs, arrow‑stuck, buffs …)
CREATE TABLE status_events (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  target_exist_id  INTEGER,
  session_id      INTEGER NOT NULL DEFAULT 0,
  creature_id      INTEGER REFERENCES creature_instances(id),
  applied_by_attack INTEGER REFERENCES attack_events(id),
  status_type      INTEGER REFERENCES status_types(id),
  location_id      INTEGER REFERENCES locations(id),
  started_at       DATETIME NOT NULL,
  ended_at         DATETIME,
  is_active        BOOLEAN GENERATED ALWAYS AS (ended_at IS NULL) STORED,
  notes            TEXT
);
CREATE INDEX idx_status_events_started ON status_events(started_at);
CREATE INDEX idx_status_events_creature_status ON status_events(creature_id, status_type);
CREATE INDEX idx_status_events_session_id ON status_events(session_id);


CREATE TABLE combat_summary (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id              INTEGER REFERENCES combat_sessions(id),
  creature_instance_id    INTEGER REFERENCES creature_instances(id),
  num_attacks             INTEGER,
  total_damage            INTEGER,
  fatal_damage            INTEGER,
  combat_duration         REAL, -- seconds
  created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

COMMIT;
