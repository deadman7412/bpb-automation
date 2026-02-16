# Services Directory

This directory contains business logic and service layer implementations.

## Purpose

Services handle:
- External integrations (Cloudflare API, scanner binary)
- Data persistence (secure storage, preferences)
- Logging and monitoring
- Core business logic

## Services

### ScannerService
Manages scanner binary execution, extraction, and result parsing.

### CloudflareApiService
Handles all Cloudflare Workers KV API interactions.

### StorageService
Manages secure credential storage and app preferences.

### LogService
Centralized logging system with tagged output.

## Guidelines

- Services should be stateless where possible
- Use dependency injection for testability
- Include comprehensive error handling
- Log all significant operations using LogService
- Follow single responsibility principle
- Mock external dependencies in tests
