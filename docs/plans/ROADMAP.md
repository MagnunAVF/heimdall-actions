# Project Heimdall Actions

## Description

Roadmap with project milestones and issues for building a Kubernetes-native CI/CD orchestration engine.

## Development Environment

- **Local Services:** Simple, localized development of individual components (API, Worker, Frontend) will rely on standard Docker containers and Docker Compose.

- **Local Cluster:** End-to-end testing and local Kubernetes development will be provisioned using `kind` (Kubernetes IN Docker).

## Project Goals

- Kubernetes-native job execution and orchestration;

- Real-time build log streaming via Server-Sent Events (SSE);

- Secure, scalable job queuing and centralized execution state management;

- Comprehensive metrics, monitoring, and alerting of the build pipelines;

- High performance and reduced database load via intelligent caching;

- End-to-end distributed tracing across API, message queue, and workers using OpenTelemetry.

## Milestone 0: Project Setup & AI-Assisted Development

Configure Claude Code as a first-class development tool for the repository by replicating the setup from an existing project.

- **Issue 0.1: Replicate Claude Code Setup:** Port the Claude Code configuration from the reference project (`CLAUDE.md`, `.claude/settings.json`, hooks, agents, skills, and MCP servers) and adapt it to this stack (Go Fiber API, Go Worker, React frontend, PostgreSQL, Redis, RabbitMQ, ClickHouse, Kubernetes) and this roadmap.

## Milestone 1: Infrastructure Core & Authentication

Establish the foundational services, database schemas, and secure access controls required to manage users and system state.

- **Issue 1.1: Keycloak OAuth Configuration:** Deploy a Keycloak instance, configure the authentication realm, and set up the OAuth 2.0 clients for both the React frontend and Go API.

- **Issue 1.2: Go Fiber API & JWT Middleware:** Initialize the Go Fiber project and implement the OAuth middleware to validate Keycloak JWT tokens and enforce route protection.

- **Issue 1.3: PostgreSQL Schema and Migrations:** Set up the Postgres database and create the initial migration scripts for the core entities (Users, Projects, Pipelines, Executions), establishing the primary data layer.

- **Issue 1.4: React Frontend Foundation:** Scaffold the React application, configure routing, and integrate the Keycloak provider for user login and session management.

- **Issue 1.5: Redis Caching Layer:** Integrate a Redis client into the Go Fiber API to cache frequently accessed data (like the image whitelist and user project permissions) to reduce load on the PostgreSQL database.

## Milestone 2: Job Dispatching & Message Queue

Develop the API layer responsible for accepting workflow definitions, validating execution parameters, and routing them to the message broker.

- **Issue 2.1: Image Whitelist & Payload Validation:** Implement the business logic within the Fiber API to receive the job payload (shell script and target image) and validate the requested image against a pre-approved list (checking the Redis cache before querying PostgreSQL).

- **Issue 2.2: RabbitMQ Publisher Integration:** Configure the Go RabbitMQ client within the Fiber API to establish a persistent connection and publish validated job payloads to a dedicated execution exchange/queue.

- **Issue 2.3: Execution State Tracking:** Create the REST endpoints to trigger a job, generate a unique execution UUID, save the initial "Pending" state to PostgreSQL, and return the tracking ID to the frontend.

## Milestone 3: Kubernetes Worker Implementation

Build the standalone Go worker service responsible for consuming queued jobs and orchestrating the actual execution within the Kubernetes cluster.

- **Issue 3.1: Worker Initialization & RabbitMQ Consumer:** Bootstrap the Go worker module, connect to RabbitMQ, and implement a robust consumer with acknowledgment handling to process incoming job requests safely.

- **Issue 3.2: Kubernetes API Integration:** Integrate `client-go` into the worker to authenticate with the target Kubernetes cluster (using service accounts or local kubeconfig) and manage cluster resources.

- **Issue 3.3: Dynamic K8s Job Spawning:** Write the logic to translate the consumed job payload into a Kubernetes `batch/v1` Job definition, injecting the shell script as a ConfigMap or inline command into the validated container image, and submit it to the cluster.

- **Issue 3.4: Execution State Sync:** Implement a watcher in the Go worker to monitor the Kubernetes Job status (Running, Succeeded, Failed) and update the central PostgreSQL database via the API.

## Milestone 4: Observability & Log Streaming

Implement the high-throughput logging pipeline to capture, store, and stream execution terminal outputs in real-time.

- **Issue 4.1: ClickHouse Initialization & Schema:** Set up ClickHouse and define the table schema optimized for time-series log data ingestion (e.g., execution_id, timestamp, log_line).

- **Issue 4.2: K8s Log Tailing & Persistence:** Enhance the Go worker to attach to the running Kubernetes Pod's standard output stream, batch the logs in memory, and bulk-insert them into ClickHouse efficiently.

- **Issue 4.3: Fiber SSE Endpoint Implementation:** Build an endpoint in the Go Fiber API using Server-Sent Events (SSE) that queries ClickHouse (or subscribes to an internal channel) to stream logs to the client as they are generated.

## Milestone 5: Frontend Dashboard & Real-time UI

Complete the user interface, allowing developers to manage projects, trigger builds, and monitor executions live.

- **Issue 5.1: Pipeline Management UI:** Build the React views to display projects, list past executions, and provide a form to submit new jobs (selecting an image from the validated dropdown and inputting a shell script).

- **Issue 5.2: Live Terminal Component:** Develop a terminal-like React component that connects to the Fiber SSE endpoint, rendering the incoming log stream in real-time with auto-scrolling capabilities.

- **Issue 5.3: Execution Status Dashboard:** Implement polling or WebSockets on the frontend to reflect the real-time execution status (Pending, Running, Success, Failed) alongside the live logs.

## Milestone 6: Infrastructure as Code & System Observability

Create the deployment configurations for the cluster and implement monitoring tools to track the health of the Heimdall Actions ecosystem.

- **Issue 6.1: Local Cluster & Service Manifests:** Define the `kind` configuration for spinning up the local cluster, and create Kubernetes manifests (or Helm charts) to deploy dependencies like Postgres, Redis, RabbitMQ, and ClickHouse.

- **Issue 6.2: Prometheus Instrumentation:** Deploy Prometheus into the cluster. Instrument both the Go API and Go Worker with Prometheus clients to expose metrics like queue depth, API latency, cache hit ratios, and job execution times.

- **Issue 6.3: Grafana Dashboards:** Deploy Grafana and connect it to Prometheus (for metrics) and ClickHouse (for logs). Build comprehensive dashboards to visualize Heimdall Actions' system health and active runner metrics.

- **Issue 6.4: OpenTelemetry Instrumentation:** Instrument the React frontend, Go Fiber API, and Go Worker with OpenTelemetry SDKs to automatically propagate context and trace requests from the initial user click, through the message broker, down to the Kubernetes job execution.

- **Issue 6.5: Distributed Tracing Backend:** Deploy an OpenTelemetry-compatible backend (such as Jaeger or Grafana Tempo) to the local `kind` cluster to collect, store, and visualize the distributed traces, integrating it into the Grafana UI.
