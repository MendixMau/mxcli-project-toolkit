# Design System — Puffin Dashboard App

## Overview
Puffin uses Material Design (Material-UI) as the foundation. This document outlines the token conventions and component strategy for the Mendix port.

## Color Palette

### Primary
- Primary Blue: #1976d2
- Primary Dark: #1565c0
- Primary Light: #42a5f5

### Secondary
- Secondary: #dc004e
- Secondary Dark: #c2185b

### Neutrals
- Text Primary: #212121
- Text Secondary: #666666
- Background: #fafafa
- Divider: #e0e0e0

## Typography

- Heading 1: 32px, weight 700
- Heading 2: 24px, weight 700
- Heading 3: 20px, weight 600
- Body: 14px, weight 400
- Caption: 12px, weight 400

## Spacing Scale

- xs: 4px
- sm: 8px
- md: 16px
- lg: 24px
- xl: 32px

## Components

### Cards
- Container for dashboard list items
- Rounded corners (4px)
- Subtle shadow on hover

### Buttons
- Primary (filled blue)
- Secondary (outline)
- Text-only (for less prominent actions)

### Dialogs
- Dashboard create/edit forms
- Confirmation dialogs

## Implementation Notes

- Mendix StyleGallery: map Material-UI color tokens
- Gallery reference: `design/design-system.html`
- Applied to all pages and snippets per `ui-preflight-pages.md`

Approved by: autonomous analysis w2-puffin-b on 2026-09-09
