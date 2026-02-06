# Flight Data Management System - Database Setup Guide

## 📋 Overview

This guide will help you set up the PostgreSQL database and Node.js API backend for the Aircraft Flight Data Management System.

## 🔧 Prerequisites

### Required Software

1. **PostgreSQL 14+**
   - Download: https://www.postgresql.org/download/
   - Or use Docker: `docker pull postgres:15`

2. **Node.js 16+**
   - Download: https://nodejs.org/
   - Check version: `node --version`

3. **npm or yarn**
   - Comes with Node.js
   - Check version: `npm --version`

---

## 📦 Installation Steps

### Step 1: Install PostgreSQL

#### Option A: Native Installation (Windows/Mac/Linux)

**Windows:**
```bash
# Download installer from postgresql.org
# Run installer and note your password
# Default port: 5432
```

**Mac (using Homebrew):**
```bash
brew install postgresql@15
brew services start postgresql@15
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

#### Option B: Docker Installation (Recommended for Development)

```bash
# Pull PostgreSQL image
docker pull postgres:15

# Run PostgreSQL container
docker run --name flight-data-postgres \
  -e POSTGRES_PASSWORD=your_password \
  -e POSTGRES_DB=flight_data \
  -p 5432:5432 \
  -d postgres:15

# Verify it's running
docker ps
```

---

### Step 2: Create Database

#### Using psql Command Line:

```bash
# Connect to PostgreSQL (will prompt for password)
psql -U postgres

# Inside psql, create database
CREATE DATABASE flight_data;

# Connect to the database
\c flight_data

# Exit psql
\q
```

#### Using Docker:

```bash
# Access PostgreSQL in container
docker exec -it flight-data-postgres psql -U postgres

# Create database
CREATE DATABASE flight_data;

# Exit
\q
```

---

### Step 3: Initialize Database Schema

```bash
# Navigate to your project directory
cd /path/to/flight-data-management

# Run the schema file
psql -U postgres -d flight_data -f database_schema.sql

# Or with Docker:
docker exec -i flight-data-postgres psql -U postgres -d flight_data < database_schema.sql
```

**Expected Output:**
```
CREATE TABLE
CREATE TABLE
CREATE TABLE
...
INSERT 0 8  (locations)
INSERT 0 12 (aircraft)
INSERT 0 8  (personnel)
```

---

### Step 4: Verify Database Setup

```bash
# Connect to database
psql -U postgres -d flight_data

# Check tables
\dt

# Should see:
# aircraft, locations, personnel, sorties, sortie_crew, 
# sortie_passengers, sortie_cargo, users

# Check data
SELECT * FROM aircraft;
SELECT * FROM locations;
SELECT * FROM personnel;

# Exit
\q
```

---

### Step 5: Install Node.js Dependencies

```bash
# Navigate to project directory
cd /path/to/flight-data-management

# Install dependencies
npm install

# Or with yarn
yarn install
```

**Dependencies installed:**
- express (web framework)
- pg (PostgreSQL client)
- cors (cross-origin requests)
- body-parser (request parsing)
- dotenv (environment variables)

---

### Step 6: Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env file with your settings
nano .env  # or use your preferred editor
```

**Update these values in .env:**
```
DB_USER=postgres
DB_HOST=localhost
DB_NAME=flight_data
DB_PASSWORD=your_actual_password
DB_PORT=5432
```

---

### Step 7: Start the API Server

```bash
# Production mode
npm start

# Development mode (auto-restart on changes)
npm run dev
```

**Expected Output:**
```
========================================
Flight Data Management API
Server running on port 3000
Environment: development
Database connected successfully at: 2024-02-06...
========================================
```

---

### Step 8: Test the API

#### Using Browser:

Visit: `http://localhost:3000/`

You should see:
```json
{
  "message": "Flight Data Management API",
  "version": "1.0.0",
  "endpoints": { ... }
}
```

#### Using curl:

```bash
# Health check
curl http://localhost:3000/health

# Get aircraft
curl http://localhost:3000/api/aircraft

# Get locations
curl http://localhost:3000/api/locations

# Get personnel
curl http://localhost:3000/api/personnel
```

#### Using Postman or Insomnia:

1. Import the API endpoints
2. Test GET requests to all endpoints
3. Test POST request to create a sortie

---

## 🔌 Updating the Web Application

Now you need to connect your HTML application to the API:

### Update JavaScript in your HTML file:

Replace the sample data loading with API calls:

```javascript
// Replace populateDropdowns function with:
async function populateDropdowns() {
    try {
        // Fetch aircraft from API
        const aircraftResponse = await fetch('http://localhost:3000/api/aircraft');
        const aircraft = await aircraftResponse.json();
        
        const tailSelect = document.getElementById('tail-number');
        aircraft.forEach(a => {
            const option = document.createElement('option');
            option.value = a.aircraft_id;
            option.textContent = `${a.tail_number} - ${a.aircraft_name}`;
            option.dataset.maxPassengers = a.max_passengers;
            option.dataset.maxCargo = a.max_cargo_weight;
            tailSelect.appendChild(option);
        });
        
        // Fetch locations
        const locationsResponse = await fetch('http://localhost:3000/api/locations');
        const locations = await locationsResponse.json();
        
        ['departure-location', 'arrival-location'].forEach(selectId => {
            const select = document.getElementById(selectId);
            locations.forEach(loc => {
                const option = document.createElement('option');
                option.value = loc.location_id;
                option.textContent = `${loc.location_code} - ${loc.location_name}`;
                select.appendChild(option);
            });
        });
        
        // Fetch personnel
        const personnelResponse = await fetch('http://localhost:3000/api/personnel');
        const personnel = await personnelResponse.json();
        
        ['pic-name', 'sic-name', 'oi-name'].forEach(selectId => {
            const select = document.getElementById(selectId);
            personnel.forEach(p => {
                const option = document.createElement('option');
                option.value = p.personnel_id;
                option.textContent = `${p.full_name} (${p.role})`;
                select.appendChild(option);
            });
        });
        
    } catch (error) {
        console.error('Error loading data:', error);
        alert('Failed to load data from server. Please check API connection.');
    }
}
```

### Update submitSortie function:

```javascript
async function submitSortie() {
    if (!validateSortieForm() || !validateCrewForm() || 
        !validatePassengersForm() || !validateCargoForm()) {
        alert('Please complete all required fields before submitting.');
        return;
    }
    
    try {
        const response = await fetch('http://localhost:3000/api/sorties', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(sortieData)
        });
        
        const result = await response.json();
        
        if (result.success) {
            const reviewContent = document.getElementById('review-content');
            reviewContent.innerHTML = `
                <div class="success-message">
                    <h3>✓ Flight Sortie Submitted Successfully</h3>
                    <p>Sortie Number: ${result.sortieNumber}</p>
                    <p>Sortie ID: ${result.sortieId}</p>
                    <p>Your flight sortie data has been saved to the database.</p>
                </div>
                <div style="text-align: center; margin-top: 30px;">
                    <button class="btn btn-primary" onclick="resetForm()">Create New Sortie</button>
                    <button class="btn btn-secondary" onclick="viewSortie(${result.sortieId})">View Sortie</button>
                </div>
            `;
        } else {
            alert('Error submitting sortie: ' + result.error);
        }
        
    } catch (error) {
        console.error('Error submitting sortie:', error);
        alert('Failed to submit sortie. Please check your connection and try again.');
    }
    
    window.scrollTo(0, 0);
}
```

---

## 📊 Database Verification Queries

After creating some sorties, run these queries to verify data:

```sql
-- View all sorties
SELECT * FROM vw_sorties_complete ORDER BY takeoff_time DESC;

-- View sorties for today
SELECT * FROM vw_sorties_complete 
WHERE DATE(takeoff_time) = CURRENT_DATE;

-- Get crew for a specific sortie
SELECT p.full_name, sc.crew_position, sc.remarks
FROM sortie_crew sc
JOIN personnel p ON sc.personnel_id = p.personnel_id
WHERE sc.sortie_id = 1;

-- Get passenger breakdown
SELECT * FROM sortie_passengers WHERE sortie_id = 1;

-- Get cargo information
SELECT * FROM sortie_cargo WHERE sortie_id = 1;

-- Daily operations summary
SELECT * FROM vw_daily_operations;

-- Aircraft utilization
SELECT tail_number, aircraft_name, total_flight_hours, 
       COUNT(*) as sorties_count
FROM aircraft a
JOIN sorties s ON a.aircraft_id = s.aircraft_id
GROUP BY a.aircraft_id, tail_number, aircraft_name, total_flight_hours
ORDER BY sorties_count DESC;
```

---

## 🚀 Production Deployment

### Security Considerations:

1. **Change default passwords**
   - Database password
   - JWT secrets
   - Session secrets

2. **Enable SSL/TLS**
   ```javascript
   // In server.js, add HTTPS
   const https = require('https');
   const fs = require('fs');
   
   const options = {
     key: fs.readFileSync('path/to/private.key'),
     cert: fs.readFileSync('path/to/certificate.crt')
   };
   
   https.createServer(options, app).listen(443);
   ```

3. **Add authentication middleware**
   - JWT tokens
   - Session management
   - Role-based access control

4. **Configure firewall**
   - Only allow specific IPs to access database
   - Use VPN for remote access

5. **Regular backups**
   ```bash
   # Automated daily backup
   pg_dump -U postgres flight_data > backup_$(date +%Y%m%d).sql
   ```

---

## 🐛 Troubleshooting

### Problem: Cannot connect to PostgreSQL

**Solution:**
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql  # Linux
brew services list  # Mac
docker ps  # Docker

# Check PostgreSQL is listening
netstat -an | grep 5432
```

### Problem: Authentication failed

**Solution:**
```bash
# Edit pg_hba.conf
sudo nano /etc/postgresql/15/main/pg_hba.conf

# Change to:
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Problem: API returns CORS errors

**Solution:**
Update CORS configuration in server.js:
```javascript
app.use(cors({
    origin: ['http://localhost:8080', 'http://your-domain.com'],
    credentials: true
}));
```

### Problem: Port 3000 already in use

**Solution:**
```bash
# Find process using port 3000
lsof -i :3000  # Mac/Linux
netstat -ano | findstr :3000  # Windows

# Kill the process or change port in .env
PORT=3001
```

---

## 📚 API Endpoints Reference

### Reference Data
- `GET /api/aircraft` - List all aircraft
- `GET /api/locations` - List all locations
- `GET /api/personnel` - List all personnel

### Sorties
- `POST /api/sorties` - Create new sortie
- `GET /api/sorties` - List sorties (paginated)
- `GET /api/sorties/:id` - Get sortie details
- `GET /api/sorties/search` - Search sorties

### Reports
- `GET /api/reports/daily?date=YYYY-MM-DD` - Daily summary
- `GET /api/reports/aircraft-utilization` - Aircraft usage
- `GET /api/reports/passenger-movement` - Passenger stats

---

## 🔄 Next Steps

1. ✅ Database created and initialized
2. ✅ API server running
3. ⬜ Update HTML application to use API
4. ⬜ Add authentication
5. ⬜ Create sortie viewing/editing functionality
6. ⬜ Build reporting dashboard
7. ⬜ Deploy to production server

---

## 📞 Support

For issues or questions:
- Check server logs: `docker logs flight-data-postgres`
- Check API logs: Console output from `npm start`
- Database queries: Use pgAdmin or DBeaver for GUI management

---

**Congratulations! Your database is ready to store flight data!** 🎉
