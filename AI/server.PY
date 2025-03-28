from flask import Flask, request, jsonify
import pandas as pd
import numpy as np
from sklearn.cluster import DBSCAN
from geopy.distance import geodesic

app = Flask(__name__)

# Load Crime Data
df = pd.read_csv('crime_data.csv')

# Preprocess Data
df.drop(columns=["Date", "Time", "Victim_Age", "Victim_Gender", "Weapon_Used", "Reported_By", "Response_Time(min)", "Arrest_Made"], inplace=True)
severity_mapping = {"Low": 1, "Moderate": 2, "Severe": 3}
df["Severity"] = df["Severity"].map(severity_mapping)

# Perform Clustering
coords = df[['Latitude', 'Longitude']].values
db = DBSCAN(eps=0.05, min_samples=3, metric='haversine').fit(np.radians(coords))
df["Cluster"] = db.labels_

# Risk Detection Function
def check_risk(user_location, threshold=0.5):
    alerts = []
    for _, row in df[df["Cluster"] != -1].iterrows():
        crime_loc = (row["Latitude"], row["Longitude"])
        distance = geodesic(user_location, crime_loc).km
        if distance < threshold:
            alerts.append({"crime": row['Crime_Type'], "severity": row['Severity'], "distance": distance})
    return alerts if alerts else [{"message": "You are in a safe zone."}]

@app.route('/check_risk', methods=['POST'])
def risk_api():
    data = request.json
    user_location = (data['latitude'], data['longitude'])
    response = check_risk(user_location)
    print(response)
    return jsonify(response)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
