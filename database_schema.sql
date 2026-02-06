-- ============================================================================
-- Aircraft Flight Data Management System - PostgreSQL Database Schema
-- Module 1: Flight Sortie Data Management
-- ============================================================================

-- Drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS sortie_cargo CASCADE;
DROP TABLE IF EXISTS sortie_passengers CASCADE;
DROP TABLE IF EXISTS sortie_crew CASCADE;
DROP TABLE IF EXISTS sorties CASCADE;
DROP TABLE IF EXISTS personnel CASCADE;
DROP TABLE IF EXISTS aircraft CASCADE;
DROP TABLE IF EXISTS locations CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- ============================================================================
-- REFERENCE TABLES
-- ============================================================================

-- Users Table (for authentication and audit)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(200) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('Pilot', 'Crew', 'Operations Manager', 'Maintenance', 'Medical Coordinator', 'Admin')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

-- Locations Table (8 operational locations)
CREATE TABLE locations (
    location_id SERIAL PRIMARY KEY,
    location_code VARCHAR(20) NOT NULL UNIQUE,
    location_name VARCHAR(100) NOT NULL,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    time_zone VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Aircraft Table
CREATE TABLE aircraft (
    aircraft_id SERIAL PRIMARY KEY,
    tail_number VARCHAR(20) NOT NULL UNIQUE,
    aircraft_name VARCHAR(100) NOT NULL,
    aircraft_type VARCHAR(50),
    max_passengers INTEGER NOT NULL DEFAULT 11,
    max_cargo_weight DECIMAL(10, 2) NOT NULL DEFAULT 2640.00,
    current_location_id INTEGER REFERENCES locations(location_id),
    status VARCHAR(50) DEFAULT 'Mission Ready' CHECK (status IN ('Mission Ready', 'Maintenance', 'Limited Use', 'Out of Service')),
    total_flight_hours DECIMAL(10, 2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Personnel Table
CREATE TABLE personnel (
    personnel_id SERIAL PRIMARY KEY,
    full_name VARCHAR(200) NOT NULL,
    rank_title VARCHAR(50),
    role VARCHAR(100) NOT NULL,
    current_location_id INTEGER REFERENCES locations(location_id),
    status VARCHAR(50) DEFAULT 'Present' CHECK (status IN ('Present', 'In-Transit', 'On Leave', 'Medical', 'Unavailable')),
    is_pilot BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- MAIN SORTIE TABLE
-- ============================================================================

CREATE TABLE sorties (
    sortie_id SERIAL PRIMARY KEY,
    sortie_number VARCHAR(50) NOT NULL UNIQUE,
    
    -- Mission Information
    mission_type VARCHAR(50) NOT NULL CHECK (mission_type IN ('CASEVAC', 'PR', 'Enabling', 'Training', 'Lift')),
    
    -- Aircraft and Locations
    aircraft_id INTEGER NOT NULL REFERENCES aircraft(aircraft_id),
    departure_location_id INTEGER NOT NULL REFERENCES locations(location_id),
    arrival_location_id INTEGER NOT NULL REFERENCES locations(location_id),
    
    -- Flight Times
    takeoff_time TIMESTAMP NOT NULL,
    landing_time TIMESTAMP NOT NULL,
    flight_duration_minutes INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (landing_time - takeoff_time))/60
    ) STORED,
    
    -- Status and Comments
    sortie_status VARCHAR(50) DEFAULT 'Planned' CHECK (sortie_status IN ('Planned', 'In-Flight', 'Completed', 'Cancelled', 'Aborted')),
    comments TEXT,
    
    -- Audit Fields
    created_by INTEGER REFERENCES users(user_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    
    -- Constraints
    CONSTRAINT valid_flight_times CHECK (landing_time > takeoff_time)
);

-- ============================================================================
-- CREW ASSIGNMENT TABLE
-- ============================================================================

CREATE TABLE sortie_crew (
    crew_assignment_id SERIAL PRIMARY KEY,
    sortie_id INTEGER NOT NULL REFERENCES sorties(sortie_id) ON DELETE CASCADE,
    personnel_id INTEGER NOT NULL REFERENCES personnel(personnel_id),
    
    -- Crew Position
    crew_position VARCHAR(50) NOT NULL CHECK (crew_position IN ('PIC', 'SIC', 'O/I', 'Other')),
    crew_position_other VARCHAR(100), -- Description if position is 'Other'
    
    -- Additional Information
    remarks TEXT,
    is_primary BOOLEAN DEFAULT true,
    
    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    UNIQUE(sortie_id, personnel_id), -- Same person can't be assigned twice to same sortie
    CHECK (crew_position != 'Other' OR crew_position_other IS NOT NULL) -- If Other, must specify
);

-- ============================================================================
-- PASSENGER TRACKING TABLE
-- ============================================================================

CREATE TABLE sortie_passengers (
    passenger_tracking_id SERIAL PRIMARY KEY,
    sortie_id INTEGER NOT NULL REFERENCES sorties(sortie_id) ON DELETE CASCADE,
    
    -- Passenger Type
    passenger_type VARCHAR(50) NOT NULL CHECK (passenger_type IN ('Military', 'Civilian', 'Contractor', 'Partner Forces', 'Other')),
    
    -- Counts
    onload_count INTEGER NOT NULL DEFAULT 0 CHECK (onload_count >= 0),
    offload_count INTEGER NOT NULL DEFAULT 0 CHECK (offload_count >= 0),
    
    -- Notes
    notes TEXT,
    
    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    UNIQUE(sortie_id, passenger_type) -- One record per passenger type per sortie
);

-- ============================================================================
-- CARGO TRACKING TABLE
-- ============================================================================

CREATE TABLE sortie_cargo (
    cargo_tracking_id SERIAL PRIMARY KEY,
    sortie_id INTEGER NOT NULL REFERENCES sorties(sortie_id) ON DELETE CASCADE,
    
    -- Weight Information
    onload_weight DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (onload_weight >= 0),
    offload_weight DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (offload_weight >= 0),
    
    -- Cargo Details
    cargo_description TEXT,
    hazmat_onboard BOOLEAN DEFAULT false,
    special_handling TEXT,
    
    -- Audit
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES for Performance
-- ============================================================================

-- Sorties indexes
CREATE INDEX idx_sorties_aircraft ON sorties(aircraft_id);
CREATE INDEX idx_sorties_departure_location ON sorties(departure_location_id);
CREATE INDEX idx_sorties_arrival_location ON sorties(arrival_location_id);
CREATE INDEX idx_sorties_takeoff_time ON sorties(takeoff_time);
CREATE INDEX idx_sorties_status ON sorties(sortie_status);
CREATE INDEX idx_sorties_mission_type ON sorties(mission_type);
CREATE INDEX idx_sorties_number ON sorties(sortie_number);

-- Crew indexes
CREATE INDEX idx_crew_sortie ON sortie_crew(sortie_id);
CREATE INDEX idx_crew_personnel ON sortie_crew(personnel_id);
CREATE INDEX idx_crew_position ON sortie_crew(crew_position);

-- Passenger indexes
CREATE INDEX idx_passengers_sortie ON sortie_passengers(sortie_id);
CREATE INDEX idx_passengers_type ON sortie_passengers(passenger_type);

-- Cargo indexes
CREATE INDEX idx_cargo_sortie ON sortie_cargo(sortie_id);

-- Aircraft indexes
CREATE INDEX idx_aircraft_tail ON aircraft(tail_number);
CREATE INDEX idx_aircraft_status ON aircraft(status);

-- Personnel indexes
CREATE INDEX idx_personnel_name ON personnel(full_name);
CREATE INDEX idx_personnel_role ON personnel(role);

-- ============================================================================
-- VIEWS for Common Queries
-- ============================================================================

-- Complete Sortie View (all data joined)
CREATE VIEW vw_sorties_complete AS
SELECT 
    s.sortie_id,
    s.sortie_number,
    s.mission_type,
    s.sortie_status,
    
    -- Aircraft
    a.tail_number,
    a.aircraft_name,
    
    -- Locations
    dl.location_code AS departure_code,
    dl.location_name AS departure_name,
    al.location_code AS arrival_code,
    al.location_name AS arrival_name,
    
    -- Times
    s.takeoff_time,
    s.landing_time,
    s.flight_duration_minutes,
    
    -- Crew (PIC)
    pic.full_name AS pic_name,
    pic.rank_title AS pic_rank,
    
    -- Totals
    COALESCE(SUM(sp.onload_count), 0) AS total_passengers_onload,
    COALESCE(SUM(sp.offload_count), 0) AS total_passengers_offload,
    COALESCE(MAX(sc.onload_weight), 0) AS cargo_onload_weight,
    COALESCE(MAX(sc.offload_weight), 0) AS cargo_offload_weight,
    
    -- Comments
    s.comments,
    
    -- Audit
    u.full_name AS created_by_name,
    s.created_at,
    s.completed_at
    
FROM sorties s
LEFT JOIN aircraft a ON s.aircraft_id = a.aircraft_id
LEFT JOIN locations dl ON s.departure_location_id = dl.location_id
LEFT JOIN locations al ON s.arrival_location_id = al.location_id
LEFT JOIN sortie_crew sc_pic ON s.sortie_id = sc_pic.sortie_id AND sc_pic.crew_position = 'PIC'
LEFT JOIN personnel pic ON sc_pic.personnel_id = pic.personnel_id
LEFT JOIN sortie_passengers sp ON s.sortie_id = sp.sortie_id
LEFT JOIN sortie_cargo sc ON s.sortie_id = sc.sortie_id
LEFT JOIN users u ON s.created_by = u.user_id
GROUP BY 
    s.sortie_id, s.sortie_number, s.mission_type, s.sortie_status,
    a.tail_number, a.aircraft_name,
    dl.location_code, dl.location_name, al.location_code, al.location_name,
    s.takeoff_time, s.landing_time, s.flight_duration_minutes,
    pic.full_name, pic.rank_title, s.comments,
    u.full_name, s.created_at, s.completed_at;

-- Daily Operations Summary View
CREATE VIEW vw_daily_operations AS
SELECT 
    DATE(takeoff_time) AS flight_date,
    mission_type,
    COUNT(*) AS total_sorties,
    SUM(flight_duration_minutes) AS total_flight_minutes,
    SUM(flight_duration_minutes) / 60.0 AS total_flight_hours
FROM sorties
WHERE sortie_status = 'Completed'
GROUP BY DATE(takeoff_time), mission_type
ORDER BY flight_date DESC, mission_type;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to generate next sortie number
CREATE OR REPLACE FUNCTION generate_sortie_number()
RETURNS VARCHAR(50) AS $$
DECLARE
    next_number INTEGER;
    year_str VARCHAR(4);
    sortie_num VARCHAR(50);
BEGIN
    year_str := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COALESCE(MAX(CAST(SUBSTRING(sortie_number FROM 8) AS INTEGER)), 0) + 1
    INTO next_number
    FROM sorties
    WHERE sortie_number LIKE 'S-' || year_str || '-%';
    
    sortie_num := 'S-' || year_str || '-' || LPAD(next_number::TEXT, 4, '0');
    
    RETURN sortie_num;
END;
$$ LANGUAGE plpgsql;

-- Function to update aircraft flight hours after sortie completion
CREATE OR REPLACE FUNCTION update_aircraft_flight_hours()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.sortie_status = 'Completed' AND OLD.sortie_status != 'Completed' THEN
        UPDATE aircraft
        SET total_flight_hours = total_flight_hours + (NEW.flight_duration_minutes / 60.0),
            updated_at = CURRENT_TIMESTAMP
        WHERE aircraft_id = NEW.aircraft_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger to auto-update aircraft flight hours
CREATE TRIGGER trg_update_aircraft_hours
    AFTER UPDATE ON sorties
    FOR EACH ROW
    WHEN (NEW.sortie_status = 'Completed')
    EXECUTE FUNCTION update_aircraft_flight_hours();

-- Triggers to auto-update timestamps
CREATE TRIGGER trg_sorties_updated_at
    BEFORE UPDATE ON sorties
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_aircraft_updated_at
    BEFORE UPDATE ON aircraft
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_personnel_updated_at
    BEFORE UPDATE ON personnel
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_passengers_updated_at
    BEFORE UPDATE ON sortie_passengers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_cargo_updated_at
    BEFORE UPDATE ON sortie_cargo
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- INITIAL DATA POPULATION
-- ============================================================================

-- Insert Locations (8 operational locations)
INSERT INTO locations (location_code, location_name, time_zone) VALUES
('LOC-01', 'Alpha Base', 'UTC+0'),
('LOC-02', 'Bravo Station', 'UTC+1'),
('LOC-03', 'Charlie Outpost', 'UTC+2'),
('LOC-04', 'Delta Forward', 'UTC+3'),
('LOC-05', 'Echo Camp', 'UTC+1'),
('LOC-06', 'Foxtrot Point', 'UTC+0'),
('LOC-07', 'Golf Sector', 'UTC+2'),
('LOC-08', 'Hotel Zone', 'UTC+3');

-- Insert Aircraft (12 aircraft from your fleet)
INSERT INTO aircraft (tail_number, aircraft_name, aircraft_type, max_passengers, max_cargo_weight, current_location_id) VALUES
('N761HG', 'Wolverine 761', 'UH-60', 11, 2640.00, 1),
('N827HG', 'Wolverine 827', 'UH-60', 11, 2640.00, 1),
('N557AC', 'Nomad 01', 'UH-60', 11, 2640.00, 2),
('N594AC', 'Nomad 02', 'UH-60', 11, 2640.00, 2),
('N551AC', 'Raptor 01', 'UH-60', 11, 2640.00, 3),
('N576AC', 'Raptor 02', 'UH-60', 11, 2640.00, 3),
('N492BA', 'Aggie94', 'UH-60', 11, 2640.00, 4),
('N480AV', 'RIPIT', 'UH-60', 11, 2640.00, 5),
('N406AV', 'Alamo', 'UH-60', 11, 2640.00, 6),
('N359PH', 'Bighorn', 'UH-60', 11, 2640.00, 7),
('UR-HZM', 'Sierra 01', 'UH-60', 11, 2640.00, 8),
('UR-HZB', 'Sierra 02', 'UH-60', 11, 2640.00, 8);

-- Insert Personnel (Sample crew members)
INSERT INTO personnel (full_name, rank_title, role, current_location_id, is_pilot) VALUES
('MAJ Smith, John', 'MAJ', 'Pilot', 1, true),
('CPT Johnson, Sarah', 'CPT', 'Pilot', 1, true),
('CPT Williams, Michael', 'CPT', 'Pilot', 2, true),
('1LT Brown, Emily', '1LT', 'Pilot', 2, true),
('CW3 Davis, Robert', 'CW3', 'Pilot', 3, true),
('SGT Martinez, Carlos', 'SGT', 'Crew Chief', 1, false),
('SGT Anderson, Lisa', 'SGT', 'Flight Medic', 1, false),
('SPC Thompson, James', 'SPC', 'Loadmaster', 2, false);

-- Insert Sample User
INSERT INTO users (username, email, full_name, role) VALUES
('admin', 'admin@flightdata.mil', 'System Administrator', 'Admin'),
('ops_manager', 'ops@flightdata.mil', 'Operations Manager', 'Operations Manager');

-- ============================================================================
-- SAMPLE QUERIES
-- ============================================================================

-- Example: Get all sorties with complete information
-- SELECT * FROM vw_sorties_complete ORDER BY takeoff_time DESC;

-- Example: Get daily operations summary
-- SELECT * FROM vw_daily_operations WHERE flight_date = CURRENT_DATE;

-- Example: Get all crew for a specific sortie
-- SELECT p.full_name, p.rank_title, sc.crew_position, sc.remarks
-- FROM sortie_crew sc
-- JOIN personnel p ON sc.personnel_id = p.personnel_id
-- WHERE sc.sortie_id = 1;

-- Example: Get passenger breakdown for a sortie
-- SELECT passenger_type, onload_count, offload_count, notes
-- FROM sortie_passengers
-- WHERE sortie_id = 1;

-- Example: Get cargo information for a sortie
-- SELECT onload_weight, offload_weight, hazmat_onboard, cargo_description
-- FROM sortie_cargo
-- WHERE sortie_id = 1;

-- ============================================================================
-- GRANT PERMISSIONS (adjust as needed for your security model)
-- ============================================================================

-- Example permissions (uncomment and adjust as needed)
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO flight_data_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO flight_data_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO flight_data_user;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

COMMENT ON DATABASE postgres IS 'Aircraft Flight Data Management System - Module 1';
COMMENT ON TABLE sorties IS 'Main table storing flight sortie information';
COMMENT ON TABLE sortie_crew IS 'Crew assignments for each sortie';
COMMENT ON TABLE sortie_passengers IS 'Passenger counts by type for each sortie';
COMMENT ON TABLE sortie_cargo IS 'Cargo weight and details for each sortie';
COMMENT ON TABLE aircraft IS 'Aircraft fleet information';
COMMENT ON TABLE locations IS 'Operational location information';
COMMENT ON TABLE personnel IS 'Crew member information';
