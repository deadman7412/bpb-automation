# Models Directory

This directory contains data models used throughout the application.

## Purpose

Models define the structure of data objects used in the app, including:
- Data transfer objects (DTOs) for API communication
- Domain models for business logic
- Configuration objects

## Models

### CleanIP
Represents a scanned Cloudflare IP with test results.

### ProxySettings
Represents the BPB Panel proxy configuration from Cloudflare Workers KV.

### ScannerConfig
Contains scanner parameters and configuration options.

### Credentials
Stores Cloudflare API authentication credentials.

## Guidelines

- All models should have `fromJson()` and `toJson()` methods for serialization
- Use immutable classes where possible
- Add `toString()` methods for debugging (but never expose sensitive data)
- Include validation methods where appropriate
- Document all fields with clear comments
