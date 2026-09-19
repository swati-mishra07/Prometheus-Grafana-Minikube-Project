# Prometheus-Grafana-Minikube-Project

Monitoring a Flask application on a local Kubernetes (Minikube) cluster using **Prometheus** for metrics collection and **Grafana** for visualization.

The app is intentionally small. It exposes simulated metrics in Prometheus text format, so the whole monitoring pipeline (app → Prometheus → Grafana) can be practiced on a low-RAM machine without running a heavy ML workload.

![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-000000?logo=flask&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Table of Contents

- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [The Flask App](#the-flask-app)
- [Prerequisites](#prerequisites)
- [Step 1: Run the App Locally (optional)](#step-1-run-the-app-locally-optional)
- [Step 2: Deploy the App on Minikube](#step-2-deploy-the-app-on-minikube)
- [Step 3: Install Prometheus with Helm](#step-3-install-prometheus-with-helm)
- [Step 4: Configure Prometheus to Scrape the Flask App](#step-4-configure-prometheus-to-scrape-the-flask-app)
- [Step 5: Install Grafana](#step-5-install-grafana)
- [Step 6: Connect Grafana to Prometheus and Build a Dashboard](#step-6-connect-grafana-to-prometheus-and-build-a-dashboard)
- [Troubleshooting](#troubleshooting)
- [Future Improvements](#future-improvements)
- [License](#license)

---

## Architecture

```
┌─────────────────────────── Minikube cluster ───────────────────────────┐
│                                                                        │
│   default namespace                     monitoring namespace           │
│  ┌────────────────────┐   scrape      ┌──────────────┐   query   ┌─────────┐
│  │ flask-metrics-app  │ ◄──────────── │  Prometheus  │ ◄──────── │ Grafana │
│  │  :5000  /metrics   │  (every N s)  │   server     │           │         │
│  └────────────────────┘               └──────────────┘           └─────────┘
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
                     kubectl port-forward → localhost:9090 / localhost:3000
```

---

## Repository Structure

| File | Purpose |
|------|---------|
| `app.py` | Flask app exposing `/` and a Prometheus-format `/metrics` endpoint |
| `dockerfile` | Builds the app image (`python:3.12-slim-bookworm`) |
| `flask-app.yaml` | Kubernetes `Deployment` and `NodePort` `Service` for the app |
| `projectflow.txt` | Raw step-by-step notes I followed while building the project |
| `LICENSE` | MIT license |

---

## The Flask App

`app.py` serves two routes on port `5000`:

| Route | Description |
|-------|-------------|
| `GET /` | Returns a JSON welcome message pointing to `/metrics` |
| `GET /metrics` | Returns metrics in Prometheus text exposition format |

Metrics exposed by `/metrics`:

| Metric | Type | Description |
|--------|------|-------------|
| `total_api_requests_total` | counter | Incremented on every call to `/metrics` |
| `request_processing_latency_seconds` | gauge | Simulated latency, random value between 0.1 and 1.5 s |
| `model_prediction_success_rate` | gauge | Simulated success rate, random value between 80 and 100 % |

> **Note:** the values are simulated with `random`, and the counter increases each time `/metrics` is scraped (including by Prometheus itself), not on real user traffic. That is fine for learning the pipeline, but a real service would instrument its actual request handlers, for example with the `prometheus_client` library.

Example output:

```
# HELP total_api_requests_total Total number of API requests
# TYPE total_api_requests_total counter
total_api_requests_total 7

# HELP request_processing_latency_seconds Latency for request processing
# TYPE request_processing_latency_seconds gauge
request_processing_latency_seconds 0.842

# HELP model_prediction_success_rate Model prediction success rate
# TYPE model_prediction_success_rate gauge
model_prediction_success_rate 93.17
```

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (Docker Engine must be running)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

Install Helm with any of:

```bash
# Windows
winget install Helm.Helm      # or: scoop install helm / choco install kubernetes-helm

# macOS
brew install helm
```

Verify it:

```bash
helm version
```

---

## Step 1: Run the App Locally (optional)

```bash
pip install flask
python app.py
```

Then open `http://localhost:5000/` and `http://localhost:5000/metrics`.

---

## Step 2: Deploy the App on Minikube

1. **Start Docker, then Minikube**

   ```bash
   minikube start
   ```

2. **Build the image**

   ```bash
   docker build -t flask-metrics-app:latest .
   ```

3. **Load the image into Minikube**

   ```bash
   minikube image load flask-metrics-app:latest
   ```

   This step is required because `flask-app.yaml` uses `imagePullPolicy: Never`, so Kubernetes will not try to pull the image from a registry.

4. **Apply the manifest** (from the repo root)

   ```bash
   kubectl apply -f flask-app.yaml
   ```

   This creates:
   - a `Deployment` named `flask-metrics-app` (1 replica, limits: `64Mi` memory / `200m` CPU)
   - a `Service` named `flask-metrics-app` of type `NodePort`, port `5000`

5. **Access the app**

   ```bash
   minikube service flask-metrics-app --url
   ```

   Open the printed URL in a browser and add `/metrics` to see the metrics.

---

## Step 3: Install Prometheus with Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus

helm install prometheus prometheus-community/prometheus \
  --namespace monitoring --create-namespace
```

Check the pods and services:

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

Open the Prometheus UI:

```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

Then visit `http://localhost:9090`.

---

## Step 4: Configure Prometheus to Scrape the Flask App

1. **Find the Flask service address**

   ```bash
   kubectl get svc
   ```

   Note the `CLUSTER-IP` and port of `flask-metrics-app` (in my run the service showed `5000:31820/TCP`).

2. **Edit the Prometheus ConfigMap**

   ```bash
   kubectl edit configmap prometheus-server -n monitoring
   ```

   Under `scrape_configs`, add a new job:

   ```yaml
   scrape_configs:
     - job_name: 'flask-app'
       static_configs:
         - targets: ['<FLASK-APP-CLUSTER-IP>:5000']
   ```

   Instead of a hard-coded ClusterIP (which can change if the service is recreated), you can use the service DNS name:

   ```yaml
   - targets: ['flask-metrics-app.default.svc.cluster.local:5000']
   ```

3. **Restart Prometheus**

   Option A, restart the deployment:

   ```bash
   kubectl rollout restart deployment prometheus-server -n monitoring
   kubectl get pods -n monitoring
   ```

   Option B, delete the pod by label and let it be recreated:

   ```bash
   kubectl get pods -n monitoring --show-labels
   kubectl delete pod -l <label-of-prometheus-server-pod> -n monitoring
   ```

4. **Verify scraping**

   ```bash
   kubectl port-forward -n monitoring svc/prometheus-server 9090:80
   ```

   In the Prometheus UI, check **Status → Targets** (the `flask-app` job should be `UP`) and query `total_api_requests_total`.

---

## Step 5: Install Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana -n monitoring --create-namespace
```

Verify:

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring     # grafana should expose port 80
```

Port-forward Grafana (for local testing only):

```bash
kubectl port-forward svc/grafana -n monitoring 3000:80
```

Open `http://localhost:3000` and log in with username `admin`. Get the generated password:

**Bash / macOS / Linux**

```bash
kubectl get secret --namespace monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

**Windows PowerShell**

```powershell
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("<PASTE-OUTPUT-HERE>"))
```

---

## Step 6: Connect Grafana to Prometheus and Build a Dashboard

1. In Grafana go to **Connections → Data sources → Add data source → Prometheus**.
2. Set the URL to the in-cluster Prometheus service:

   ```
   http://prometheus-server.monitoring.svc.cluster.local:80
   ```

3. Scroll down and click **Save & test**.
4. Go to **Dashboards → New dashboard → Add visualization** and try these queries:

   | Panel | Query |
   |-------|-------|
   | Total requests | `total_api_requests_total` |
   | Request rate (per second) | `rate(total_api_requests_total[5m])` |
   | Latency | `request_processing_latency_seconds` |
   | Success rate | `model_prediction_success_rate` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Pod stuck in `ErrImageNeverPull` | The image is not inside Minikube. Run `minikube image load flask-metrics-app:latest` again. |
| `flask-app` target is `DOWN` in Prometheus | Check the target IP/port in the ConfigMap, or use the service DNS name. Confirm with `kubectl get svc`. |
| Config change has no effect | Restart the `prometheus-server` deployment (see Step 4). |
| Can't reach Prometheus or Grafana on localhost | Make sure the `kubectl port-forward` command is still running in its terminal. |
| Metrics don't show in Grafana | Confirm the data source URL and that `Save & test` succeeds. |

---

## Future Improvements

- Add real alerting rules (Prometheus Alertmanager or Grafana alerts), for example when `model_prediction_success_rate` drops below a threshold.
- Replace the simulated metrics with real instrumentation using `prometheus_client` (counters and histograms in the request handlers).
- Use a `ServiceMonitor` or pod annotations for automatic scrape discovery instead of editing the ConfigMap by hand.
- Export the Grafana dashboard as JSON and commit it to the repo.
- Add screenshots of the Prometheus targets page and the Grafana dashboard.

---

## License

This project is licensed under the [MIT License](LICENSE).
