# Azure Cost Visibility Dashboard

**A fully automated Azure FinOps system that monitors daily cloud spending, detects cost anomalies, enforces tagging compliance, and delivers structured morning reports — giving complete financial visibility before costs become a problem.**

---

## Project Overview

Most teams running Azure have no real-time visibility into their spending. They discover budget overruns when the monthly bill arrives — too late to act. This project eliminates that blind spot entirely.

An Azure Function runs automatically every morning, queries the Cost Management API for yesterday's spending, scans all resources for missing governance tags, compares current spend against a 7-day historical baseline to detect anomalies, persists every report to Azure Table Storage, and dispatches a structured email report via Logic Apps. All cost and compliance data is visualised in a live Grafana dashboard connected directly to Azure Table Storage.

---

## Architecture

**Flow:**
```
Timer fires every morning at 8AM
        ↓
Azure Function (PowerShell) authenticates via Managed Identity
        ↓
Queries Azure Cost Management API
Gets yesterday's spend broken down by service
        ↓
Queries 7-day spend history
Calculates average and detects anomalies above threshold
        ↓
Queries Azure Resource Graph
Identifies all resources missing required tags (Environment, Owner)
        ↓
Saves structured report to Azure Table Storage (costreports table)
        ↓
Sends HTTP POST to Logic App with full report payload
        ↓
Logic App delivers formatted email:
  - Financial Overview: total spend + anomaly status
  - Cloud Governance: untagged resource count
        ↓
Grafana dashboard (via Infinity plugin + SAS token)
reads live data from Table Storage and visualises:
  - Daily Costs and Detected Anomalies
  - Non-Compliant Resources over time
```

**Service breakdown:**

- **Azure Functions (Consumption Plan, Windows, PowerShell 7.4)** — Timer triggered serverless function orchestrating the entire pipeline
- **Azure Cost Management API** — Retrieves actual daily spend grouped by service name
- **Azure Resource Graph** — Subscription-wide query for resources missing required governance tags
- **Azure Table Storage (costreports)** — Persistent NoSQL store for every daily cost and compliance snapshot
- **Azure Logic App** — HTTP triggered workflow delivering structured email reports via Outlook
- **Grafana (Azure Managed)** — Live dashboard connected to Table Storage via Infinity plugin and SAS token authentication — no credentials stored in Grafana
- **Managed Identity** — Function App authenticates to all Azure APIs without any stored keys or secrets
- **Application Insights** — Function execution monitoring and telemetry

---

## Project Focus

**My role on this project was Cloud Architect, FinOps Engineer, and Automation Engineer.**

- Designed the end-to-end cost monitoring and governance architecture
- Provisioned and configured all Azure resources
- Enabled System Assigned Managed Identity with Reader and Cost Management Reader roles at subscription scope
- Wrote the PowerShell automation script integrating Cost Management API, Resource Graph API, and Table Storage
- Configured Logic App workflow with structured JSON schema and dynamic email body
- Integrated Grafana using the Infinity plugin with SAS token based authentication — avoiding credential exposure while enabling live data queries
- Validated the full pipeline end-to-end including live email delivery and Grafana data visualisation

The PowerShell function code was developed collaboratively using AI tooling based on my architectural design and requirements. This reflects how modern cloud engineers work — defining the system, making architectural decisions, and leveraging available tools to implement efficiently.

---

## Key Technical Decisions

**Grafana over Azure Workbooks:**
Chose Azure Managed Grafana instead of native Azure Workbooks to demonstrate cross-platform observability skills. Grafana is the industry standard monitoring tool in cloud operations environments. Connecting it to Azure Table Storage via the Infinity plugin with SAS token authentication shows both Azure and Grafana proficiency simultaneously.

**Infinity Plugin with SAS Token:**
Rather than storing storage account credentials inside Grafana, a SAS token scoped to the costreports table was used as the data source URL parameter. This keeps authentication lightweight and avoids credential management complexity while maintaining security.

**Managed Identity over API Keys:**
All Azure API calls — Cost Management and Resource Graph — are authenticated using the Function App's system-assigned managed identity. No keys, no secrets, no rotation required.

---

## Visual Proof

Screenshots of all deployed resources, function execution logs, Logic App designer, email report received, Storage Table data, and Grafana dashboard are available in the `screenshots/` folder.

---

## Repository Structure

```
├── run.ps1                      # PowerShell timer trigger function
├── screenshots/                 # Azure Portal and Grafana screenshots
└── README.md
```

---

## Skills Demonstrated

**FinOps and Cost Management**
- Azure Cost Management API integration for real-time spend retrieval
- 7-day baseline anomaly detection with configurable threshold
- Daily spend breakdown by service name
- Automated morning reporting before costs escalate

**Cloud Governance**
- Azure Resource Graph subscription-wide tag compliance scanning
- Identifies resources missing required Environment and Owner tags
- Compliance count tracked over time in persistent storage

**Serverless Architecture**
- Azure Functions Consumption Plan with PowerShell 7.4 runtime
- Timer trigger with daily schedule
- Managed Identity authentication — zero stored credentials
- Environment variables for all configuration

**Observability and Dashboarding**
- Azure Managed Grafana connected to live Azure Table Storage
- Infinity plugin with SAS token authentication
- Daily Costs and Anomalies panel
- Non-Compliant Resources panel with historical trend

**Event-Driven Automation**
- Logic App HTTP trigger receiving structured JSON payload
- Dynamic email body using payload fields — totalSpend, anomalyStatus, untaggedCount
- Structured JSON schema defined on trigger for reliable field mapping

**Secure Configuration**
- System Assigned Managed Identity on Function App
- Reader role assigned at subscription scope
- Cost Management Reader role assigned at subscription scope
- SAS token used in Grafana data source URL

---

## Business Problem Solved

Finance teams and cloud administrators in growing companies have no daily visibility into Azure spending. By the time the monthly invoice arrives the damage is done — budgets are blown, anomalies go unnoticed, and untagged resources make cost attribution impossible.

This system solves all three problems simultaneously. Every morning the team receives a structured report showing exactly what was spent, whether anything spiked abnormally, and how many resources are violating governance policies. The Grafana dashboard provides persistent historical context that a one-off email cannot.

The combination of automated reporting, anomaly detection, and tag compliance monitoring in a single serverless pipeline is what a dedicated FinOps engineer would build for an enterprise environment.




