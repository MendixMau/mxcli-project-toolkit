# Harbour Berth Booking System - Complete KB

This document consolidates all KB files for the Harbour Berth Booking System.

## Key Entities Summary

- **Vessel, VesselType** - vessel master data, AIS feed integration
- **Berth, BerthSlot, AllocationRule** - berth management and allocation
- **Booking, BookingRequest** - booking lifecycle management
- **TariffRate, ServiceCharge, TariffCalculation** - tariff & billing
- **ApprovalStep, ApprovalDecision** - approval workflow

## Key Screens

- Booking Request Form (agent submission)
- Booking Status View (tracking)
- Berth Utilization Dashboard (operations)
- Officer Review Queue (approvals)
- Tariff Estimation & Administration
- Vessel Registry Lookup

## Business Rules

Allocation engine runs nightly. Tariff calculated at submission and locked. Approval chain blocks progression. AIS feed updates vessel master data hourly. No double-booking allowed.

## Roles

Agent, Ops Manager, Officer (Triage/Safety/Environment/Finance), Finance, Admin.

## Integration Points

- AIS Feed (inbound, hourly)
- Payment Gateway (outbound, stub in MVP)
- Email Notification (outbound, stub in MVP)
- Reporting Export (file system, stub in MVP)
