from flask import Flask, request, jsonify
import pandas as pd
import numpy as np
from sklearn.cluster import DBSCAN
from geopy.distance import geodesic
import logging

app = Flask(__name__)

# Configuration
CRIME_DATA_PATH = 'crime_data.csv'
DBSCAN_EPS = 0.05  # ~5km
DBSCAN_MIN_SAMPLES = 3
RISK_THRESHOLD_KM = 0.5

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def load_and_preprocess_data():
    """Load and preprocess crime data."""
    try:
        df = pd.read_csv(CRIME_DATA_PATH)
        df.drop(columns=["Date", "Time", "Victim_Age", "Victim_Gender", 
                         "Weapon_Used", "Reported_By", "Response_Time(min)", 
                         "Arrest_Made"], inplace=True, errors='ignore')
        
        severity_mapping = {"Low": 1, "Moderate": 2, "Severe": 3}
        df["Severity"] = df["Severity"].map(severity_mapping)
        return df
    except Exception as e:
        logger.error(f"Error loading data: {e}")
        raise

# Load data on startup
try:
    df = load_and_preprocess_data()
    coords = df[['Latitude', 'Longitude']].values
    db = DBSCAN(eps=DBSCAN_EPS, min_samples=DBSCAN_MIN_SAMPLES, metric='haversine').fit(np.radians(coords))
    df["Cluster"] = db.labels_
    clustered_df = df[df["Cluster"] != -1]
    logger.info("Data loaded and clustered successfully")
except Exception as e:
    logger.error(f"Initialization failed: {e}")
    raise

def check_risk(user_location, threshold=RISK_THRESHOLD_KM):
    """Check for nearby crime clusters."""
    alerts = []
    for _, row in clustered_df.iterrows():
        crime_loc = (row["Latitude"], row["Longitude"])
        distance = geodesic(user_location, crime_loc).km
        if distance < threshold:
            alerts.append({
                "crime": row['Crime_Type'],
                "severity": row['Severity'],
                "distance": round(distance, 4),
                "cluster": int(row['Cluster'])
            })
    return alerts if alerts else [{"message": "You are in a safe zone."}]

@app.route('/check_risk', methods=['POST'])
def risk_api():
    """Endpoint for risk assessment."""
    try:
        data = request.get_json()
        if not data or 'latitude' not in data or 'longitude' not in data:
            return jsonify({"error": "Latitude and longitude are required"}), 400
        
        try:
            lat = float(data['latitude'])
            lng = float(data['longitude'])
            if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
                raise ValueError("Invalid coordinate range")
        except ValueError as e:
            return jsonify({"error": f"Invalid coordinates: {e}"}), 400

        user_location = (lat, lng)
        response = check_risk(user_location)
        return jsonify({"status": "success", "data": response})
    
    except Exception as e:
        logger.error(f"API error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)