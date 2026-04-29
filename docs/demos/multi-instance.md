---
layout: default
title: Multiple firewalls in one box
permalink: /demos/multi-instance/
eyebrow: Whiteboard
summary: This one is a conversation, not a deployment. What if a single piece of Cisco hardware ran several independent firewalls at once?
---

## What is being shown

A whiteboard, not a virtual machine. The audience already saw a single virtual firewall handle four demos. This is the next conversation: when one firewall is not enough, what does running several in one box look like, and where does that run.

## The pitch in three lines

- It runs on Cisco's physical hardware (the Firepower 4100 and 4200 series), not in the cloud.
- Each "instance" is a fully independent firewall, with its own memory, processor share, and admin login.
- The use case is keeping tenants apart, or rolling out an upgrade on a copy before the production copy.

## When it is a good fit

- A managed service provider running VPN gateways for several customers in one chassis.
- A regulated environment that wants policy isolation between business units, with one operations team to run the hardware.
- An upgrade pattern where you start a new firewall instance on the same hardware, test it, then cut over without touching the live one.

## When it is the wrong tool

- Small environments. A single virtual firewall covers the load.
- Anywhere paired failover is required at the box level. Multiple instances on one box do not replace clustering across two boxes.
- Cloud-only deployments. This is a hardware feature.

## Why it is not in the build

A one-day Azure budget is for the four demos that the firewall and cloud manager can show end to end. Multi-instance ships on physical hardware, which is not what this workshop runs on. The whiteboard slot is enough to explain when it would matter.

## What to draw on the board

```text
+------------------------------+
|   Cisco Firepower 4200 box   |
|                              |
|  +-----------+ +-----------+ |
|  | Firewall  | | Firewall  | |
|  | instance A| | instance B| |
|  | tenant 1  | | tenant 2  | |
|  +-----------+ +-----------+ |
|         |             |      |
|       VPN gateway   ZTAA app |
|       for tenant 1  for      |
|                     tenant 2 |
+------------------------------+
```

Each instance has its own policy in the cloud manager and its own front-door address. The chassis itself enforces the resource split.
