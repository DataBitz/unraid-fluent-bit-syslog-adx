# Fluent Bit Syslog Forwarder to Azure Data Explorer (Unraid Template) `v1.0.1`

An Unraid application template for **Fluent Bit** (`fluent/fluent-bit:latest`) configured to ingest network Syslog traffic over both **UDP and TCP** on port 514, supporting both **RFC 3164 (BSD legacy)** and **RFC 5424 (modern IETF)** formats. Parses and maps fields to match the Log Analytics schema using Lua, and streams data directly into **Azure Data Explorer (ADX)** / Kusto.

---

## Prerequisites & Architecture Overview

Before deploying the Unraid template, you need to set up an **App Registration** in Microsoft Entra ID (Azure AD), configure your **Azure Data Explorer** database schema and permissions, and manually place the configuration files into your Unraid appdata directory.

```
+-------------------+      UDP/TCP 514      +----------------------------------------+        HTTPs Ingest        +-----------------------+
|  Network Device   | --------------------> | Fluent Bit Container (Host Network)    | -------------------------> | Azure Data Explorer   |
| (Router, Switches)|                       |  └─ syslog-to-la.lua Transformation    |                            |  └─ Database: MyDatabase|
+-------------------+                       +----------------------------------------+                            +-----------------------+
```

---

## Step 1: Microsoft Entra ID (Azure AD) Setup

Fluent Bit uses a **Service Principal** (App Registration) to authenticate securely with Azure Data Explorer using OAuth 2.0 client credentials.

### 1.1 Create App Registration
1. Log in to the [Azure Portal](https://portal.azure.com/).
2. Navigate to **Microsoft Entra ID** > **App registrations** > click **+ New registration**.
3. Name the application (e.g., `FluentBit-ADX-Ingestor`).
4. Set **Supported account types** to **Accounts in this organizational directory only (Single tenant)**.
5. Leave Redirect URI blank and click **Register**.
6. **Capture Identifiers:**
   * **Application (client) ID**
   * **Directory (tenant) ID**

### 1.2 Generate Client Secret
1. Inside your new App Registration, select **Certificates & secrets** from the left menu.
2. Select the **Client secrets** tab and click **+ New client secret**.
3. Enter a description (e.g., `FluentBit Unraid Secret`) and select an expiration period (e.g., 180 days / 12 months).
4. Click **Add**.
5. **Capture Secret Value:** Copy the string in the **Value** column immediately (*this value will be permanently masked once you leave the page*).

---

## Step 2: Azure Data Explorer (ADX) Setup

You can use a standard ADX cluster or an **Azure Data Explorer Free Cluster**.

### 2.1 Create ADX Cluster & Database
1. Navigate to [Azure Data Explorer Free](https://aka.ms/adx.free) or create an ADX cluster via the Azure Portal.
2. Create a cluster and set up a new database (e.g., `MyDatabase`).
3. Note your **Data Ingestion URI** (e.g., `https://ingest-mycluster.region.kusto.windows.net`).

### 2.2 Create Table & Ingestion Mapping
Open the **Azure Data Explorer Web UI** ([https://dataexplorer.azure.com/](https://dataexplorer.azure.com/)), connect to your cluster and database (`MyDatabase`), and execute the following KQL control commands:

#### 1. Create the `Syslog` Table
```kusto
.create table Syslog (
    TimeGenerated: datetime,
    SourceSystem: string,
    EventTime: datetime,
    CollectorHostName: string,
    Computer: string,
    HostIP: string,
    HostName: string,
    Facility: string,
    SeverityLevel: string,
    ProcessName: string,
    ProcessID: int,
    SyslogMessage: string,
    Type: string,
    _ResourceId: string,
    _SubscriptionId: string
)
```

#### 2. Create the JSON Ingestion Mapping
```kusto
.create-or-alter table Syslog ingestion json mapping "SyslogMapping"
'['
'  {"column": "TimeGenerated",     "Properties": {"Path": "$.timestamp"}},'
'  {"column": "EventTime",         "Properties": {"Path": "$.timestamp"}},'
'  {"column": "SourceSystem",      "Properties": {"Path": "$.log.SourceSystem"}},'
'  {"column": "CollectorHostName", "Properties": {"Path": "$.log.CollectorHostName"}},'
'  {"column": "Computer",          "Properties": {"Path": "$.log.Computer"}},'
'  {"column": "HostName",          "Properties": {"Path": "$.log.HostName"}},'
'  {"column": "HostIP",            "Properties": {"Path": "$.log.HostIP"}},'
'  {"column": "Facility",          "Properties": {"Path": "$.log.Facility"}},'
'  {"column": "SeverityLevel",     "Properties": {"Path": "$.log.SeverityLevel"}},'
'  {"column": "ProcessName",       "Properties": {"Path": "$.log.ProcessName"}},'
'  {"column": "ProcessID",         "Properties": {"Path": "$.log.ProcessID"}},'
'  {"column": "SyslogMessage",     "Properties": {"Path": "$.log.SyslogMessage"}},'
'  {"column": "Type",              "Properties": {"Path": "$.log.Type"}}'
']'
```

#### 3. Grant Ingestion Role to App Registration
Replace `<AZURE_CLIENT_ID>` and `<AZURE_TENANT_ID>` with your credentials captured in Step 1:
```kusto
.add database MyDatabase ingestors ('aadapp=<AZURE_CLIENT_ID>;<AZURE_TENANT_ID>') 'Fluent Bit Syslog Ingestor App'
```

#### 4. Configure 30-Day Retention Policy (Recommended for Free Tier)
By default, Azure Data Explorer sets retention to 100 years. If using the **ADX Free Tier (10 GB storage limit)**, you should configure a 30-day retention policy so expired logs are automatically and permanently purged to prevent hitting your quota:
```kusto
.alter-merge table Syslog policy retention softdelete = 30d recoverability = disabled
```
*(Setting `recoverability = disabled` ensures expired data is immediately purged rather than kept in a 14-day soft-delete buffer that counts against your 10 GB quota).*

---

## Step 3: Prepare Host Configuration Files

Before launching the container, you must manually download or create the [`fluent-bit.yaml`](https://github.com/DataBitz/unraid-fluent-bit-syslog-adx/blob/main/fluent-bit.yaml) and [`syslog-to-la.lua`](https://github.com/DataBitz/unraid-fluent-bit-syslog-adx/blob/main/syslog-to-la.lua) files inside your Unraid appdata directory (`/mnt/user/appdata/fluent-bit`).

Run this single command directly in your Unraid terminal:

```mkdir -p /mnt/user/appdata/fluent-bit && \
wget -qO /mnt/user/appdata/fluent-bit/fluent-bit.yaml https://raw.githubusercontent.com/DataBitz/unraid-fluent-bit-syslog-adx/development/fluent-bit.yaml && \
wget -qO /mnt/user/appdata/fluent-bit/syslog-to-la.lua https://raw.githubusercontent.com/DataBitz/unraid-fluent-bit-syslog-adx/development/syslog-to-la.lua
```

---

## Step 4: Deployment Checklist

Ensure you have all required parameters ready before launching the Unraid template:

| Environment Variable | Description | Example / Requirement |
| :--- | :--- | :--- |
| `SYSLOG_PORT` | Listening UDP/TCP port for network syslog | `514` |
| `AZURE_TENANT_ID` | Microsoft Entra Directory (tenant) ID | `00000000-0000-0000-0000-000000000000` |
| `AZURE_CLIENT_ID` | App Registration Application (client) ID | `11111111-1111-1111-1111-111111111111` |
| `AZURE_CLIENT_SECRET` | App Registration Client Secret Value | `~xyz123...` |
| `ADX_DATA_INGESTION_URI` | ADX Data Ingestion Endpoint | **REQUIRED** (e.g. `https://ingest-mycluster.region.kusto.windows.net`) |
| `ADX_DATABASE_NAME` | ADX Database Name | **REQUIRED** (e.g. `MyDatabase`) |
| `ADX_TABLE_NAME` | Destination Kusto Table | `Syslog` |
| `ADX_MAPPING_NAME` | Destination JSON Mapping Name | `SyslogMapping` |

---

## Step 5: Installation on Unraid

### Automatic Installation (Community Applications)
1. In Unraid, navigate to the **Apps** tab.
2. Search for `fluent-bit-syslog-adx`.
3. Click **Install**.
4. Fill in the required environment variables captured in Step 4.
5. Click **Apply**.

### Manual Template Installation
1. Copy `unraid-fluent-bit-syslog-adx.xml` to your Unraid flash drive:
   ```bash
   mkdir -p /boot/config/plugins/community.applications/private/DataBitz
   wget -qO /boot/config/plugins/community.applications/private/DataBitz/unraid-fluent-bit-syslog-adx.xml https://raw.githubusercontent.com/DataBitz/unraid-fluent-bit-syslog-adx/main/unraid-fluent-bit-syslog-adx.xml
   ```
2. In the Unraid Web GUI, go to **Apps** > **Private** (or **Docker** > **Add Container**).
3. Select **fluent-bit-syslog-adx**.
4. Fill in your Azure AD credentials and ADX endpoint parameters, then click **Apply**.

---

## Step 6: Verification & Testing

### 1. Send Test Packets from Unraid
Test both RFC 3164 and RFC 5424 syslog ingestion over UDP and TCP:

```bash
# Test RFC 3164 (Legacy BSD syslog) via UDP
echo "<13>Oct 20 00:00:00 unraid testapp[1234]: Fluent Bit ADX test packet via UDP (RFC 3164)" | nc -u -w1 127.0.0.1 514

# Test RFC 5424 (Modern IETF syslog) via TCP
echo "<13>1 2026-10-20T00:00:00.000Z unraid testapp 1234 - - Fluent Bit ADX test packet via TCP (RFC 5424)" | nc -w1 127.0.0.1 514

# Alternatively using the standard logger command:
logger -n 127.0.0.1 -P 514 -d -t testapp "Fluent Bit test RFC 3164 via UDP"
logger -n 127.0.0.1 -P 514 -T --rfc5424 -t testapp "Fluent Bit test RFC 5424 via TCP"
```

### 2. Verify Container Execution
Check the container logs to ensure successful transformation and batch delivery:

```bash
docker logs --tail 30 fluent-bit-syslog-adx
```
*Expected Output:* `[info] [engine] flush chunk ... succeeded at retry 0`

### 3. Query Azure Data Explorer
Run this query in the ADX Web UI to confirm arrival:

```kusto
Syslog
| where ProcessName == "testapp"
| order by TimeGenerated desc
| take 10
```