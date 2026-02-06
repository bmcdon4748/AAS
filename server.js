// ============================================================================
// Flight Data Management API - Node.js/Express Backend
// ============================================================================

const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 3000;

// ============================================================================
// MIDDLEWARE
// ============================================================================

app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// ============================================================================
// DATABASE CONNECTION
// ============================================================================

const pool = new Pool({
    user: process.env.DB_USER || 'postgres',
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'flight_data',
    password: process.env.DB_PASSWORD || 'your_password',
    port: process.env.DB_PORT || 5432,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
    if (err) {
        console.error('Database connection error:', err);
    } else {
        console.log('Database connected successfully at:', res.rows[0].now);
    }
});

// ============================================================================
// REFERENCE DATA ENDPOINTS
// ============================================================================

// Get all aircraft
app.get('/api/aircraft', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT aircraft_id, tail_number, aircraft_name, aircraft_type,
                   max_passengers, max_cargo_weight, status, 
                   current_location_id, total_flight_hours
            FROM aircraft
            WHERE is_active = true
            ORDER BY aircraft_name
        `);
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching aircraft:', err);
        res.status(500).json({ error: 'Failed to fetch aircraft' });
    }
});

// Get all locations
app.get('/api/locations', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT location_id, location_code, location_name, time_zone
            FROM locations
            WHERE is_active = true
            ORDER BY location_code
        `);
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching locations:', err);
        res.status(500).json({ error: 'Failed to fetch locations' });
    }
});

// Get all personnel
app.get('/api/personnel', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT personnel_id, full_name, rank_title, role, is_pilot, status
            FROM personnel
            WHERE is_active = true
            ORDER BY full_name
        `);
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching personnel:', err);
        res.status(500).json({ error: 'Failed to fetch personnel' });
    }
});

// ============================================================================
// SORTIE ENDPOINTS
// ============================================================================

// Create new sortie (complete transaction)
app.post('/api/sorties', async (req, res) => {
    const client = await pool.connect();
    
    try {
        await client.query('BEGIN');
        
        const { sortie, crew, passengers, cargo } = req.body;
        
        // 1. Generate sortie number
        const sortieNumberResult = await client.query('SELECT generate_sortie_number()');
        const sortieNumber = sortieNumberResult.rows[0].generate_sortie_number;
        
        // 2. Insert sortie
        const sortieResult = await client.query(`
            INSERT INTO sorties (
                sortie_number, mission_type, aircraft_id,
                departure_location_id, arrival_location_id,
                takeoff_time, landing_time, comments, 
                created_by, sortie_status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'Completed')
            RETURNING sortie_id
        `, [
            sortieNumber,
            sortie.missionType,
            sortie.tailNumber,
            sortie.depLocation,
            sortie.arrLocation,
            sortie.takeoffTime,
            sortie.landingTime,
            sortie.comments || null,
            1 // Default user ID - replace with actual authenticated user
        ]);
        
        const sortieId = sortieResult.rows[0].sortie_id;
        
        // 3. Insert crew members
        if (crew.pic && crew.pic.name) {
            await client.query(`
                INSERT INTO sortie_crew (sortie_id, personnel_id, crew_position, remarks)
                VALUES ($1, $2, 'PIC', $3)
            `, [sortieId, crew.pic.name, crew.pic.remarks || null]);
        }
        
        if (crew.sic && crew.sic.name) {
            await client.query(`
                INSERT INTO sortie_crew (sortie_id, personnel_id, crew_position, remarks)
                VALUES ($1, $2, 'SIC', $3)
            `, [sortieId, crew.sic.name, crew.sic.remarks || null]);
        }
        
        if (crew.oi && crew.oi.name) {
            await client.query(`
                INSERT INTO sortie_crew (sortie_id, personnel_id, crew_position, remarks)
                VALUES ($1, $2, 'O/I', $3)
            `, [sortieId, crew.oi.name, crew.oi.remarks || null]);
        }
        
        // Additional crew
        if (crew.additional && crew.additional.length > 0) {
            for (const member of crew.additional) {
                if (member.name) {
                    await client.query(`
                        INSERT INTO sortie_crew (sortie_id, personnel_id, crew_position, crew_position_other, remarks)
                        VALUES ($1, $2, 'Other', $3, $4)
                    `, [sortieId, member.name, member.position, member.remarks || null]);
                }
            }
        }
        
        // 4. Insert passengers
        const passengerTypes = ['military', 'civilian', 'contractor', 'partner', 'other'];
        const passengerTypeMap = {
            'military': 'Military',
            'civilian': 'Civilian',
            'contractor': 'Contractor',
            'partner': 'Partner Forces',
            'other': 'Other'
        };
        
        for (const type of passengerTypes) {
            if (passengers[type]) {
                await client.query(`
                    INSERT INTO sortie_passengers (
                        sortie_id, passenger_type, onload_count, offload_count, notes
                    ) VALUES ($1, $2, $3, $4, $5)
                `, [
                    sortieId,
                    passengerTypeMap[type],
                    passengers[type].onload || 0,
                    passengers[type].offload || 0,
                    passengers[type].notes || null
                ]);
            }
        }
        
        // 5. Insert cargo
        await client.query(`
            INSERT INTO sortie_cargo (
                sortie_id, onload_weight, offload_weight,
                cargo_description, hazmat_onboard, special_handling
            ) VALUES ($1, $2, $3, $4, $5, $6)
        `, [
            sortieId,
            cargo.onloadWeight || 0,
            cargo.offloadWeight || 0,
            cargo.description || null,
            cargo.hazmat || false,
            cargo.specialHandling || null
        ]);
        
        await client.query('COMMIT');
        
        res.status(201).json({
            success: true,
            sortieId: sortieId,
            sortieNumber: sortieNumber,
            message: 'Sortie created successfully'
        });
        
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('Error creating sortie:', err);
        res.status(500).json({ 
            success: false,
            error: 'Failed to create sortie',
            details: err.message 
        });
    } finally {
        client.release();
    }
});

// Get all sorties (with pagination)
app.get('/api/sorties', async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 50;
        const offset = parseInt(req.query.offset) || 0;
        
        const result = await pool.query(`
            SELECT * FROM vw_sorties_complete
            ORDER BY takeoff_time DESC
            LIMIT $1 OFFSET $2
        `, [limit, offset]);
        
        const countResult = await pool.query('SELECT COUNT(*) FROM sorties');
        
        res.json({
            sorties: result.rows,
            total: parseInt(countResult.rows[0].count),
            limit: limit,
            offset: offset
        });
    } catch (err) {
        console.error('Error fetching sorties:', err);
        res.status(500).json({ error: 'Failed to fetch sorties' });
    }
});

// Get single sortie by ID (complete details)
app.get('/api/sorties/:id', async (req, res) => {
    try {
        const sortieId = req.params.id;
        
        // Get main sortie info
        const sortieResult = await pool.query(`
            SELECT * FROM vw_sorties_complete WHERE sortie_id = $1
        `, [sortieId]);
        
        if (sortieResult.rows.length === 0) {
            return res.status(404).json({ error: 'Sortie not found' });
        }
        
        // Get crew
        const crewResult = await pool.query(`
            SELECT sc.crew_position, sc.crew_position_other, sc.remarks,
                   p.full_name, p.rank_title, p.role
            FROM sortie_crew sc
            JOIN personnel p ON sc.personnel_id = p.personnel_id
            WHERE sc.sortie_id = $1
        `, [sortieId]);
        
        // Get passengers
        const passengersResult = await pool.query(`
            SELECT passenger_type, onload_count, offload_count, notes
            FROM sortie_passengers
            WHERE sortie_id = $1
        `, [sortieId]);
        
        // Get cargo
        const cargoResult = await pool.query(`
            SELECT onload_weight, offload_weight, cargo_description,
                   hazmat_onboard, special_handling
            FROM sortie_cargo
            WHERE sortie_id = $1
        `, [sortieId]);
        
        res.json({
            sortie: sortieResult.rows[0],
            crew: crewResult.rows,
            passengers: passengersResult.rows,
            cargo: cargoResult.rows[0] || null
        });
        
    } catch (err) {
        console.error('Error fetching sortie details:', err);
        res.status(500).json({ error: 'Failed to fetch sortie details' });
    }
});

// Search sorties
app.get('/api/sorties/search', async (req, res) => {
    try {
        const { 
            aircraft, 
            location, 
            missionType, 
            startDate, 
            endDate,
            sortieNumber 
        } = req.query;
        
        let query = 'SELECT * FROM vw_sorties_complete WHERE 1=1';
        const params = [];
        let paramCount = 1;
        
        if (aircraft) {
            query += ` AND tail_number = $${paramCount}`;
            params.push(aircraft);
            paramCount++;
        }
        
        if (location) {
            query += ` AND (departure_code = $${paramCount} OR arrival_code = $${paramCount})`;
            params.push(location);
            paramCount++;
        }
        
        if (missionType) {
            query += ` AND mission_type = $${paramCount}`;
            params.push(missionType);
            paramCount++;
        }
        
        if (startDate) {
            query += ` AND takeoff_time >= $${paramCount}`;
            params.push(startDate);
            paramCount++;
        }
        
        if (endDate) {
            query += ` AND takeoff_time <= $${paramCount}`;
            params.push(endDate);
            paramCount++;
        }
        
        if (sortieNumber) {
            query += ` AND sortie_number ILIKE $${paramCount}`;
            params.push(`%${sortieNumber}%`);
            paramCount++;
        }
        
        query += ' ORDER BY takeoff_time DESC LIMIT 100';
        
        const result = await pool.query(query, params);
        res.json(result.rows);
        
    } catch (err) {
        console.error('Error searching sorties:', err);
        res.status(500).json({ error: 'Failed to search sorties' });
    }
});

// ============================================================================
// REPORTING ENDPOINTS
// ============================================================================

// Daily operations summary
app.get('/api/reports/daily', async (req, res) => {
    try {
        const date = req.query.date || new Date().toISOString().split('T')[0];
        
        const result = await pool.query(`
            SELECT * FROM vw_daily_operations
            WHERE flight_date = $1
            ORDER BY mission_type
        `, [date]);
        
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching daily report:', err);
        res.status(500).json({ error: 'Failed to fetch daily report' });
    }
});

// Aircraft utilization report
app.get('/api/reports/aircraft-utilization', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT 
                a.tail_number,
                a.aircraft_name,
                a.total_flight_hours,
                COUNT(s.sortie_id) AS total_sorties,
                SUM(s.flight_duration_minutes) / 60.0 AS flight_hours_period,
                AVG(s.flight_duration_minutes) AS avg_flight_minutes
            FROM aircraft a
            LEFT JOIN sorties s ON a.aircraft_id = s.aircraft_id 
                AND s.sortie_status = 'Completed'
                AND s.takeoff_time >= CURRENT_DATE - INTERVAL '30 days'
            WHERE a.is_active = true
            GROUP BY a.aircraft_id, a.tail_number, a.aircraft_name, a.total_flight_hours
            ORDER BY total_sorties DESC
        `);
        
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching aircraft utilization:', err);
        res.status(500).json({ error: 'Failed to fetch aircraft utilization' });
    }
});

// Passenger movement summary
app.get('/api/reports/passenger-movement', async (req, res) => {
    try {
        const startDate = req.query.startDate || new Date(Date.now() - 30*24*60*60*1000).toISOString();
        const endDate = req.query.endDate || new Date().toISOString();
        
        const result = await pool.query(`
            SELECT 
                sp.passenger_type,
                SUM(sp.onload_count) AS total_onload,
                SUM(sp.offload_count) AS total_offload,
                COUNT(DISTINCT sp.sortie_id) AS sorties_count
            FROM sortie_passengers sp
            JOIN sorties s ON sp.sortie_id = s.sortie_id
            WHERE s.takeoff_time BETWEEN $1 AND $2
                AND s.sortie_status = 'Completed'
            GROUP BY sp.passenger_type
            ORDER BY total_onload DESC
        `, [startDate, endDate]);
        
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching passenger movement:', err);
        res.status(500).json({ error: 'Failed to fetch passenger movement' });
    }
});

// ============================================================================
// HEALTH CHECK
// ============================================================================

app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/', (req, res) => {
    res.json({ 
        message: 'Flight Data Management API',
        version: '1.0.0',
        endpoints: {
            aircraft: 'GET /api/aircraft',
            locations: 'GET /api/locations',
            personnel: 'GET /api/personnel',
            sorties: {
                list: 'GET /api/sorties',
                create: 'POST /api/sorties',
                get: 'GET /api/sorties/:id',
                search: 'GET /api/sorties/search'
            },
            reports: {
                daily: 'GET /api/reports/daily',
                aircraftUtilization: 'GET /api/reports/aircraft-utilization',
                passengerMovement: 'GET /api/reports/passenger-movement'
            }
        }
    });
});

// ============================================================================
// ERROR HANDLING
// ============================================================================

app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ 
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// ============================================================================
// START SERVER
// ============================================================================

app.listen(PORT, () => {
    console.log(`\n========================================`);
    console.log(`Flight Data Management API`);
    console.log(`Server running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`========================================\n`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, closing server...');
    pool.end(() => {
        console.log('Database pool closed');
        process.exit(0);
    });
});
