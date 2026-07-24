

# OPNsense Plugin Development for Japanese NTT DS-LITE and MAP-E Support

## 1. Executive Summary: NTT Japan IPv6 Transition Technologies

### 1.1 Technology Overview

#### 1.1.1 Primary Protocol: MAP-E (Mapping of Address and Port with Encapsulation)

**MAP-E** serves as the cornerstone of NTT's IPv6 transition strategy, deployed across NTT East and NTT West fiber infrastructure since **April 2013** . This stateless protocol enables IPv4 connectivity over native IPv6 access networks through **algorithmic address and port mapping** rather than dynamic NAT table management. The fundamental innovation lies in embedding IPv4 addressing information directly within the IPv6 prefix structure, allowing Border Relay (BR) devices to operate without per-connection state maintenance.

The operational model positions MAP-E as a **scalable, deterministic alternative to Carrier-Grade NAT**. Multiple subscribers share a single public IPv4 address through **Port Set Identification (PSID)**, with each subscriber's allocated port range mathematically derived from their delegated IPv6 prefix. This eliminates session table exhaustion risks and enables horizontal scaling of BR infrastructure through anycast deployment. For OPNsense plugin development, MAP-E's stateless nature simplifies failover and redundancy design while introducing complexity in parameter calculation and validation.

NTT markets this service under the commercial brand **"v6plus"**, operated through JPIX (Japan Internet Exchange) . The deployment represents one of the world's largest production MAP-E implementations, with extensive operational experience informing stable, well-documented configuration patterns.

#### 1.1.2 Secondary Protocol: DS-LITE (Dual-Stack Lite) for Select Deployments

**DS-LITE** (Dual-Stack Lite, RFC 6333) operates as NTT's secondary IPv4 transition mechanism, primarily deployed through partner Virtual Network Enablers (VNEs) under the **"Transix"** service brand . Unlike MAP-E's stateless architecture, DS-LITE employs **stateful IPv4-in-IPv6 tunneling** combined with Carrier-Grade NAT44 at the AFTR (Address Family Transition Router).

The architectural distinction creates meaningful trade-offs. DS-LITE's **B4 (Basic Bridging Broadband)** element at the CPE performs simple encapsulation without address translation, centralizing all NAT functionality at the AFTR. This simplifies CPE implementation but concentrates scaling constraints and failure modes at the carrier edge. Session state maintenance at the AFTR introduces logging requirements for compliance and complicates high-availability designs compared to MAP-E's stateless operation.

For OPNsense plugin architecture, supporting both protocols ensures comprehensive coverage of Japanese ISP deployments, with automatic protocol detection or manual selection based on service identification.

#### 1.1.3 Historical Context: NTT East/West MAP-E Deployment Since April 2013

NTT's **April 2013 MAP-E launch** established Japan as a global leader in IPv6 transition technology deployment, predating comparable Western ISP initiatives by several years . This extended operational history has produced a mature ecosystem with:

- **Validated interoperability** across multiple CPE vendor implementations
- **Community-developed tools** for parameter calculation and troubleshooting
- **Documented operational quirks** and edge case handling
- **Regional variation patterns** between NTT East and NTT West infrastructure

The deployment's longevity ensures configuration stability—parameters and addressing schemes have remained sufficiently consistent to enable reliable automation. However, the **evolution from 1G to 10G service tiers** introduced prefix delegation changes that plugin implementations must accommodate.

### 1.2 Service Tiers and Prefix Allocation

#### 1.2.1 1G Plans: /56 IPv6 Prefix Delegation

NTT's **1Gbps residential plans** historically provided **/64 IPv6 prefixes without Prefix Delegation (PD)** capability for subscribers without the "Hikari Denwa" (ひかり電話) residential phone service . This limitation created significant configuration complexity, as the absence of router advertisements (RA) and PD prevented automatic prefix propagation to downstream networks.

The workaround requires **manual specification of routed prefix information** in CPE configuration, extracting the /64 from the WAN interface's assigned address. Community documentation for OpenWRT describes this as configuring "relay mode" for RA/DHCPv6/NDP-Proxy services with explicit `ip6prefix` directives . More recent infrastructure upgrades have improved this situation, with **/56 prefix delegation with PD** now common even for basic 1G plans.

The /56 allocation provides **256 /64 subnets**—sufficient for typical residential deployments with guest networks, IoT segmentation, and multiple VLANs. From a MAP-E perspective, the /56 length constrains available bits for EA-field extraction, requiring careful parameter calculation.

#### 1.2.2 10G Plans: /48 or /40 IPv6 Prefix Delegation

**10Gbps premium tiers** receive substantially larger IPv6 delegations, with **/56 prefix delegation standard** and reports of **/48 or /40 allocations** in certain deployments . The /40 prefix has become particularly significant for MAP-E implementation because:

- Its **40-bit boundary aligns with hexadecimal address representation**, simplifying visual parsing
- Expanded address space enables **more flexible EA-bit field allocation**
- Community-developed calculators typically expect /40 input for NTT parameter derivation

The 10G plan's **IPoE-only architecture** (no PPPoE option) eliminates encapsulation overhead and simplifies prefix acquisition. Guaranteed PD capability regardless of Hikari Denwa subscription eliminates the configuration complexity plaguing legacy 1G deployments.

| Service Tier | Typical Prefix | PD Support | MAP-E Implications |
|-------------|--------------|-----------|-------------------|
| 1G (legacy) | /64 | No (without Hikari Denwa) | Manual prefix extraction required |
| 1G (current) | /56 | Yes | Standard automatic configuration |
| 10G | /56 to /40 | Yes | Optimal for parameter calculation |

#### 1.2.3 Parameter Derivation: AFTR Address and Port Mapping Calculated from Delegated Prefix

NTT's MAP-E implementation uniquely **derives all tunnel parameters from the delegated IPv6 prefix itself**, eliminating DHCPv6 option dependencies used in some other MAP-E deployments . This embedded parameter approach requires CPE devices to implement:

1. **IPv4 prefix extraction** from EA-bits in the delegated prefix
2. **PSID calculation** for port range determination
3. **AFTR address derivation** through prefix-embedded addressing
4. **EA-bit length and PSID offset** application per deployment-specific rules

Community-developed calculators automate this derivation, accepting a /40 IPv6 prefix and outputting complete MAP-E configuration sets . For OPNsense plugin development, integrating equivalent calculation logic enables **fully automatic configuration**—a significant usability improvement over manual parameter transcription.

## 2. MAP-E Technical Architecture

### 2.1 Core Protocol Mechanics

#### 2.1.1 Stateless Address and Port Mapping: Algorithmic Binding of IPv4 Address/Port to IPv6 Prefix

MAP-E's **stateless mapping algorithm** (RFC 7597) establishes deterministic relationships between IPv6 prefixes and IPv4 addressing parameters without requiring per-connection state maintenance . The algorithm operates through **bit-field extraction and mathematical transformation**:

- The **Rule IPv6 Prefix** (provider aggregate) identifies the MAP domain
- **EA-bits (Embedded Address bits)** encode IPv4 address suffix and PSID information
- The **PSID (Port Set ID)** determines subscriber-specific port range allocation

This stateless property enables **anycast BR deployment**—any Border Relay instance can process packets for any subscriber without session affinity or state synchronization. Failover occurs instantaneously, and infrastructure scaling requires only additional BR capacity rather than session table expansion.

The mathematical determinism ensures consistent behavior: identical IPv6 prefixes always yield identical IPv4 parameters, regardless of calculation timing or location. For OPNsense implementation, this eliminates server communication requirements and enables **fully offline configuration** once the delegated prefix is obtained.

#### 2.1.2 Encapsulation Mode: IPv4-in-IPv6 Tunneling to AFTR

MAP-E employs **direct IPv4-in-IPv6 encapsulation** (RFC 2473), preserving the complete original IPv4 packet—including header and payload—within an IPv6 transport envelope. The encapsulation structure consists of:

| Field | Value | Description |
|-------|-------|-------------|
| IPv6 Source | CPE delegated prefix address | Tunnel endpoint identification |
| IPv6 Destination | AFTR/BR IPv6 address | Border Relay location |
| Next Header | 4 (IPv4) | Payload type indication |
| Payload | Complete IPv4 packet | Unmodified original packet |

This **transparency-preserving approach** contrasts with translation-based alternatives (MAP-T, NAT64) that modify packet headers and potentially break applications with embedded address dependencies. The trade-off is **40 bytes of IPv6 header overhead**, reducing effective MTU from 1500 to 1460 bytes for standard Ethernet.

The AFTR performs **symmetric decapsulation**: removing the IPv6 header, extracting the IPv4 packet, and forwarding to the global Internet. Return traffic follows the reverse path, with the AFTR encapsulating incoming IPv4 packets based on destination address-to-prefix mapping.

#### 2.1.3 Port Set Identification (PSID): Customer-Specific Port Range Allocation

The **PSID mechanism** enables multiple subscribers to share a single IPv4 address through **non-overlapping, algorithmically assigned port ranges**. The port space division follows RFC 7597 specifications:

- **PSID length** (typically 6-8 bits): Determines number of subscribers per IPv4 address (64-256)
- **PSID offset** (typically 4-6 bits): Reserves low-numbered ports for special purposes
- **PSID value**: Extracted from delegated prefix, selects specific port set

For NTT deployments, community reports indicate **variable port allocations**: v6plus assigns **15 port groups (240 ports)**, while OCN/plala assignments reach **63 port groups (1008 ports)** . This variation reflects different PSID offset/length configurations across service offerings.

| PSID Length | Subscribers/IPv4 | Ports/Subscriber | Typical Use Case |
|-------------|---------------|------------------|----------------|
| 6 bits | 64 | ~1008 | Premium residential, small business |
| 8 bits | 256 | ~240 | Standard residential, high density |

The **port range constraint** creates application compatibility considerations. High-connection-count applications (BitTorrent, some gaming protocols, enterprise VPNs) may exhaust allocated ports, while services requiring specific well-known ports face fundamental limitations. OPNsense plugin implementations should provide **connection monitoring and port utilization visibility** to help diagnose such issues.

#### 2.1.4 EA-Bit Length and PSID Offset: Critical Parameters for CPE Configuration

**EA-bit length** and **PSID offset** represent the most technically nuanced MAP-E parameters, directly controlling address sharing ratios and port allocation characteristics:

| Parameter | Function | Typical NTT Values |
|-----------|----------|------------------|
| EA-bit length | Bits from IPv6 prefix encoding IPv4+PSID | 20-25 bits |
| IPv4 prefix length | Shared portion of provider's IPv4 block | 15 bits |
| PSID length | Bits for port set identification | 6-8 bits |
| PSID offset | Reserved low-port bits | 4-6 bits |

The **interdependency** of these parameters requires careful validation: EA-bit length must equal (32 - IPv4 prefix length) + PSID length for consistent mapping. Incorrect configuration produces **complete connectivity failure** with challenging diagnostic characteristics—packets may reach the BR but be dropped due to parameter mismatch, with no explicit error indication.

For NTT's v6plus service, community analysis suggests **25-bit EA length, 15-bit IPv4 prefix, 8-bit PSID** as typical configuration , though these values should be treated as operational observations rather than officially confirmed specifications.

### 2.2 Address Mapping Algorithm

#### 2.2.1 IPv4 Prefix Extraction from IPv6 Delegated Prefix

The **IPv4 prefix extraction process** operates on bit-field boundaries within the delegated IPv6 prefix. For a typical NTT /40 delegation:

1. **Normalize** the delegated prefix to 128-bit representation
2. **Extract EA-bits** from positions determined by Rule IPv6 Prefix length
3. **Partition EA-bits** into IPv4 address suffix (most significant portion) and PSID (least significant portion)
4. **Combine** IPv4 suffix with Rule IPv4 Prefix to form complete address

The **bit-level precision** required creates implementation sensitivity. Off-by-one errors in offset calculation produce invalid configurations that appear structurally correct but fail in operation. Community calculators provide validated reference implementations for cross-checking .

#### 2.2.2 Port Range Calculation: PSID-Based Port Set Derivation

**Port range calculation** transforms the extracted PSID value into specific TCP/UDP port numbers available to the subscriber. The algorithm:

```
available_ports = 65536 - (2^PSID_offset)  // Exclude reserved range
ports_per_psid = available_ports / (2^PSID_length)
base_port = (PSID × ports_per_psid) + (2^PSID_offset)
port_range = [base_port, base_port + ports_per_psid - 1]
```

The **non-contiguous nature** of PSID-based port allocation (when offset > 0) requires careful NAT implementation. FreeBSD's `map-e-portset` pf extension handles this efficiently, but userspace implementations must explicitly manage port selection across potentially distributed ranges.

#### 2.2.3 BR/DMR (Border Relay/Decapsulating MAP Relay) Address Determination

The **AFTR/BR IPv6 address** serves as the tunnel destination for all encapsulated traffic. NTT's deployment uses **prefix-embedded addressing** rather than DHCPv6 option distribution, with the AFTR address derived from specific bits of the delegated prefix combined with known network prefixes.

This embedded approach **eliminates discovery protocol dependencies** but requires accurate knowledge of NTT's addressing scheme. Community documentation has compiled **known AFTR addresses by region**, with values like `2404:9200:225:100::64` reported for specific deployments . The addressing scheme appears to use **anycast distribution**, with identical AFTR addresses resolving to different physical locations based on network topology.

#### 2.2.4 NTT-Specific Parameter Calculator: Community-Developed Tools for /40 Prefix Conversion

The complexity of NTT MAP-E parameter derivation has motivated extensive **community tool development**. These calculators implement bit-field extraction algorithms validated against operational deployments:

| Tool Type | Implementation | Input | Output |
|-----------|---------------|-------|--------|
| Web calculator | JavaScript/HTML | /40 IPv6 prefix | Complete parameter set |
| Command-line | Python/Shell | /40 IPv6 prefix | Configuration snippets |
| Library function | Multiple languages | Prefix + parameters | Validated configuration |

The reference implementation at **ipv4.web.fc2.com**  provides web-based calculation with output including: IPv4 address, port ranges, AFTR address, EA-bit length, PSID length, PSID offset, and PSID value. For OPNsense plugin development, **embedding equivalent calculation logic** eliminates external dependencies and enables automatic configuration.

### 2.3 Tunnel Establishment and Maintenance

#### 2.3.1 Softwire Initiation: CPE-to-AFTR Tunnel Setup

MAP-E uses **connectionless softwire establishment**—no explicit tunnel setup protocol is required. The CPE simply:

1. **Configures** the tunnel interface with local (delegated prefix) and remote (AFTR) addresses
2. **Installs** default IPv4 route through tunnel interface
3. **Begins encapsulation** of IPv4 traffic to AFTR destination

This **implicit establishment** eliminates handshake latency and protocol state machines but creates **diagnostic challenges**: misconfiguration produces silent failure rather than explicit error indication. The plugin must implement **connectivity validation** through active probing (ICMP echo, HTTP requests) to confirm operational status.

#### 2.3.2 Encapsulation Headers: IPv6 Outer Header with IPv4 Payload

The **encapsulation header structure** preserves IPv4 packet integrity:

| Layer | Header | Size | Notes |
|-------|--------|------|-------|
| Outer | IPv6 | 40 bytes | Standard header, no extension headers typical |
| Inner | IPv4 | 20-60 bytes | Original header preserved, including options |
| Payload | Application | Variable | Unmodified |

**Header field handling** requires attention to:
- **Traffic Class**: May be copied from IPv4 TOS or set to zero
- **Flow Label**: Typically zero unless flow identification implemented
- **Don't Fragment**: IPv4 DF bit affects PMTUD behavior for encapsulated path

#### 2.3.3 MTU Considerations: 1460 Bytes Effective MTU After Encapsulation Overhead

The **40-byte IPv6 header overhead** reduces effective MTU, with cascading effects:

| Scenario | Effective MTU | MSS Clamp | Notes |
|----------|-------------|-----------|-------|
| Standard Ethernet | 1460 bytes | 1420 bytes | Most common deployment |
| With PPPoE | 1452 bytes | 1412 bytes | Legacy access encapsulation |
| Conservative | 1280 bytes | 1240 bytes | Guaranteed IPv6 minimum |

**MSS clamping** is essential for reliable TCP operation. The recommended **1420-byte MSS** (1460 - 40 TCP header) prevents PMTUD dependence while maintaining reasonable efficiency . UDP-based applications require explicit handling or reduced datagram sizes.

#### 2.3.4 Path MTU Discovery Handling for Encapsulated Traffic

**PMTUD for MAP-E** involves nested IPv4 and IPv6 mechanisms:

- **IPv6 PMTUD**: Routers drop oversized packets, return ICMPv6 "Packet Too Big"
- **IPv4 PMTUD**: Endpoints receive ICMP "Fragmentation Needed" or rely on TCP MSS

The **encapsulation nesting** creates failure modes: IPv6 PMTUD messages must be **translated or propagated** to IPv4 senders, but ICMP filtering and middlebox interference often break this path. Conservative MSS clamping provides **reliable fallback** for TCP, while UDP applications remain vulnerable.

OPNsense plugin implementations should: **enable TCP MSS clamping by default**, **monitor for PMTUD failures**, and **provide diagnostic tools** for MTU path verification.

## 3. DS-LITE Technical Architecture

### 3.1 Core Protocol Mechanics

#### 3.1.1 Stateful Tunneling: IPv4-in-IPv6 Encapsulation to AFTR

DS-LITE establishes **stateful IPv4-in-IPv6 tunnels** between the CPE (B4 element) and AFTR, with critical architectural differences from MAP-E:

| Aspect | MAP-E | DS-LITE |
|--------|-------|---------|
| State | Stateless at BR/AFTR | Stateful at AFTR |
| NAT location | CPE (with PSID constraints) | AFTR (dynamic NAT44) |
| Port allocation | Fixed PSID-based | Dynamic per-connection |
| Failover | Instant, no state sync | Requires state sync or reconnection |
| Scalability | Linear with bandwidth | Constrained by session table size |

The **stateful AFTR operation** requires **per-connection tracking** for NAT44 translation, with session tables mapping private B4 addresses/ports to public IPv4 addresses/ports. This creates **memory and processing scaling constraints** proportional to active connection count, not just subscriber count.

#### 3.1.2 NAT44 Functionality: Carrier-Grade NAT at AFTR

The AFTR's **NAT44 function** performs dynamic address and port translation:

- **Dynamic port allocation** from shared pool as connections establish
- **Session state maintenance** with timeout and refresh management
- **Connection logging** for compliance and abuse tracing
- **Hairpinning support** for subscriber-to-subscriber traffic

The **double-NAT scenario** (CPE NAT + AFTR NAT) common in residential deployments exacerbates application compatibility issues. Some DS-LITE implementations recommend **disabling CPE NAT** for pure B4 operation, but this requires RFC 1918 address coordination with the AFTR.

#### 3.1.3 B4 (Basic Bridging Broadband) Element: CPE Tunnel Endpoint

The **B4 element** provides minimal CPE functionality:

- **Encapsulation**: IPv4 packets → IPv6 headers → AFTR
- **Decapsulation**: IPv6 packets from AFTR → IPv4 → internal network
- **No NAT44**: Original IPv4 addresses preserved (or CPE NAT applied separately)

RFC 6333 specifies **192.0.0.2/32** for B4 tunnel interface, with AFTR at **192.0.0.1/32**, creating a standardized point-to-point configuration. This simplicity enabled early DS-LITE deployment with minimal CPE firmware modifications.

#### 3.1.4 AFTR Discovery: DHCPv6 Option 64 or Static Configuration

| Discovery Method | Mechanism | NTT Deployment |
|-----------------|-----------|--------------|
| DHCPv6 Option 64 | AFTR_NAME in DHCPv6 response | Limited support |
| Static configuration | Hardcoded AFTR address | Primary method |
| DNS-based | FQDN resolution | Some regions |

NTT's DS-LITE (Transix) deployment **primarily uses static AFTR configuration**, with community-documented addresses like `2001:c28:5:301::11` for specific service regions . DHCPv6 Option 64 support exists but is not universally deployed, making **static configuration with regional defaults** the reliable approach for OPNsense plugin implementation.

### 3.2 Tunnel Implementation

#### 3.2.1 IPIP6 Mode: IP-in-IP IPv6 Mode for FreeBSD gif Interfaces

FreeBSD's **generic tunnel interface (`gif`)** provides native **IPIP6 (IPv4-in-IPv6) encapsulation** for DS-LITE:

```bash
# Interface creation and configuration
ifconfig gif0 create
ifconfig gif0 tunnel <local_ipv6> <aftr_ipv6>
ifconfig gif0 inet 192.0.0.2 192.0.0.1 netmask 255.255.255.255
```

The `gif` interface appears as a **standard point-to-point link** for routing and firewall purposes, with encapsulation/decapsulation handled transparently by the kernel. This mature, well-tested infrastructure requires no special kernel modifications for DS-LITE operation.

#### 3.2.2 Dynamic AFTR Address Learning vs. Static Configuration

**Dynamic discovery** through DHCPv6 Option 64 offers operational flexibility:
- Automatic adaptation to AFTR infrastructure changes
- Load distribution across multiple AFTR instances
- Simplified provisioning without manual address entry

However, **NTT's limited DHCPv6 Option 64 deployment** makes static configuration more reliable. The optimal OPNsense plugin approach: **attempt dynamic discovery, fall back to static configuration with regional defaults**, and provide explicit manual override.

#### 3.2.3 Session State Management: Connection Tracking Requirements

The **B4 element itself is stateless**—no per-connection tracking required for encapsulation. However, **operational considerations** suggest implementing:

- **Keepalive mechanisms** to detect AFTR availability
- **Connection monitoring** for diagnostic visibility
- **Rapid reconnection** on tunnel failure

FreeBSD's `gif` interface provides **link state indication** based on tunnel activity, enabling integration with OPNsense's gateway monitoring framework for failover detection.

#### 3.2.4 IPv4 NAT Disablement: Pure Routing Through Tunnel

**Critical configuration requirement**: DS-LITE B4 operation requires **disabling IPv4 NAT on the tunnel interface** to avoid triple-NAT scenarios (CPE NAT + potential internal NAT + AFTR NAT). The CPE must **route IPv4 traffic without address translation**, preserving original addresses for AFTR-side NAT44.

This "pure routing" mode creates **user experience challenges**: subscribers expect traditional NAT behavior, and diagnostic tools may report "private IP on WAN" as problematic. OPNsense plugin UI should **clearly communicate this architectural requirement** and provide **connection verification tools** to confirm proper operation.

## 4. Router Implementation Patterns

### 4.1 Home Router Implementations (CPE)

#### 4.1.1 OpenWRT MAP-E Configuration

##### 4.1.1.1 Required Packages: `map` Package for MAP-E Support

The **OpenWRT `map` package** provides comprehensive MAP-E/MAP-T support through integration with the **netifd network interface daemon**. Key components:

| Component | Function |
|-----------|----------|
| `map.sh` | Protocol handler script for netifd integration |
| Kernel modules | MAP encapsulation/decapsulation |
| `mapcalc` | Command-line parameter calculation utility |

Installation requires explicit package selection and system reboot, creating friction that OPNsense's integrated distribution can eliminate .

##### 4.1.1.2 Interface Configuration: WAN6 with MAP Protocol

OpenWRT's **two-interface architecture** separates concerns:

```bash
# WAN6: IPv6 prefix acquisition
config interface 'wan6'
    option proto 'dhcpv6'
    option reqaddress 'try'
    option reqprefix 'auto'

# wan_map: MAP-E tunnel
config interface 'wan_map'
    option proto 'map'
    option maptype 'map-e'
    option tunlink 'wan6'
    # ... derived parameters
```

This separation enables **independent troubleshooting**: IPv6 connectivity issues can be diagnosed before MAP-E tunnel establishment, and tunnel failures are isolated from prefix acquisition problems.

##### 4.1.1.3 Parameter Input: Manual AFTR, IPv4 Prefix, EA-bits, PSID-bits, PSID Offset

The **manual parameter burden** in OpenWRT requires users to:

1. Obtain delegated IPv6 prefix from WAN6 status
2. Input to community calculator tool
3. Transcribe **8+ parameters** to UCI configuration
4. Validate and restart network services

This **error-prone process** motivates OPNsense plugin automation: **automatic parameter calculation from delegated prefix** with manual override for edge cases.

##### 4.1.1.4 Firewall Integration: Zone-Based Policy for MAP Interface

OpenWRT's **zone-based firewall** assigns MAP interfaces to WAN zone:

```bash
config zone
    option name 'wan'
    list network 'wan'
    list network 'wan6'
    list network 'wan_map'  # MAP-E interface
    option input 'DROP'
    option output 'ACCEPT'
    option forward 'DROP'
```

**PSID-aware NAT** requires community patches for proper port range enforcement—an area where FreeBSD 14.0+'s native `map-e-portset` support provides cleaner implementation .

#### 4.1.2 OpenWRT DS-LITE Configuration

##### 4.1.2.1 Required Packages: `ds-lite` Package

The **`ds-lite` package** provides B4 functionality with substantially simpler configuration than MAP-E, reflecting DS-LITE's reduced parameter complexity.

##### 4.1.2.2 AFTR Address Configuration: Static or DHCPv6-Derived

```bash
config interface 'dslite'
    option proto 'dslite'
    option peeraddr '2001:c28:5:301::11'  # Static AFTR
    option tunlink 'wan6'
```

**Dynamic discovery** via DHCPv6 Option 64 supported but not universally deployed.

##### 4.1.2.3 Interface Setup: dslite Protocol with Peer Address

Minimal configuration: **protocol type, AFTR address, underlying interface**. The `dslite` protocol handler manages tunnel creation and routing installation.

##### 4.1.2.4 NAT Handling: IPv4 NAT Disablement for Pure Tunnel Operation

Critical configuration: **exclude DS-LITE interface from masquerade**:

```bash
config zone
    option name 'wan'
    option masq '1'  # NAT for other WAN interfaces
    # ds-lite interface in separate zone without masq
```

#### 4.1.3 Consumer Router Firmware (QNAP, Synology, Yamaha)

##### 4.1.3.1 Pre-configured ISP Profiles: "v6plus" for MAP-E, "Transix" for DS-LITE

**Commercial firmware** abstracts protocol complexity through **ISP-branded profiles**:

| Profile | Protocol | Use Case |
|---------|----------|----------|
| "v6plus" | MAP-E | NTT primary service |
| "Transix" | DS-LITE | NTT partner/VNE service |
| "OCN Virtual Connect" | MAP-E | NTT subsidiary ISP |
| "BIGLOBE IPv6" | MAP-E | Alternative provider |

These profiles **embed known-good parameters**—AFTR addresses, typical prefix lengths, MTU/MSS values—enabling **one-click configuration** for supported services .

##### 4.1.3.2 Automatic Parameter Detection: ISP-Specific AFTR Address Databases

Advanced implementations maintain **regional AFTR address databases**, selecting appropriate values based on:
- Detected prefix allocation patterns
- User-selected region or service type
- DNS-based service discovery

##### 4.1.3.3 Web UI Configuration: Simplified Mode Selection

**Progressive disclosure** design:
- **Simple mode**: ISP profile selection only
- **Advanced mode**: Individual parameter access for troubleshooting or non-standard deployments

### 4.2 Enterprise Router Considerations

#### 4.2.1 Scalability: Multiple Subscriber Management

Enterprise scenarios requiring **multiple MAP-E/DS-LITE instances**:
- Multi-tenant buildings with per-unit IPv4 connectivity
- Redundant ISP connections with independent tunnels
- Aggregated bandwidth through multiple subscriptions

OPNsense's **interface and routing framework** supports this through multiple tunnel interfaces with independent parameter sets and policy-based routing.

#### 4.2.2 High Availability: Redundant AFTR Pathing

| Protocol | HA Approach | Implementation |
|----------|-----------|----------------|
| MAP-E | Anycast AFTR addresses | Multiple tunnels to same anycast address |
| DS-LITE | Multiple AFTR with state sync | Complex; often single AFTR with rapid failover |

MAP-E's **stateless operation** enables simpler HA: multiple tunnel interfaces to different AFTR addresses with **routing protocol or policy-based selection**.

#### 4.2.3 Policy-Based Routing: Traffic Classification for Tunneled vs. Native IPv6

Enterprise networks may prefer **native IPv6 where available**, using MAP-E/DS-LITE tunnels only for IPv4 destinations. OPNsense's **firewall-based routing** enables:
- Destination-based tunnel selection
- Application-specific routing policies
- Fallback to tunnel when native IPv6 unavailable

#### 4.2.4 Logging and Accounting: Per-Subscriber Session Tracking

**Compliance and operational requirements** may mandate:
- Connection logging for security audit
- Traffic volume accounting for billing
- Performance monitoring for SLA verification

MAP-E's **stateless operation** complicates session-level logging—flows must be inferred from packet inspection or connection tracking state. DS-LITE's **stateful AFTR** provides natural logging points, though CPE visibility is limited.

## 5. FreeBSD/OPNsense Platform Specifics

### 5.1 Current FreeBSD MAP-E Support Status

#### 5.1.1 FreeBSD 14.0+ Integration: Native MAP-E Kernel Support Commit

**Critical infrastructure**: FreeBSD commit `2aa21096c7349390f22aa5d06b373a575baed1b4` (August 2023) introduced **native MAP-E kernel support** :

| Component | Implementation |
|-----------|---------------|
| `map` interface driver | Kernel-native encapsulation/decapsulation |
| `map-e-portset` pf extension | PSID-based port range enforcement |
| EA-bit extraction | Algorithmic parameter calculation |
| IPv6 prefix integration | Delegation-aware configuration |

This **kernel-level implementation** eliminates userspace tunneling overhead, enabling **line-rate performance** critical for 10G deployments.

#### 5.1.2 OPNsense 24.1+ Base: FreeBSD 14.1 Foundation Enabling MAP-E Capabilities

OPNsense **24.1 (January 2024)** upgraded to **FreeBSD 14.1**, inheriting native MAP-E support . Available capabilities:

- Kernel MAP-E encapsulation/decapsulation
- `map-e-portset` pf extension for port range NAT
- `gif` interface IPIP6 mode for DS-LITE
- DHCPv6-PD prefix delegation infrastructure

#### 5.1.3 Missing Userland Integration: No GUI or Automated Configuration

**Critical gap**: Despite kernel support, OPNsense **24.1+ lacks**:
- GUI configuration for MAP-E/DS-LITE interfaces
- Automated parameter calculation from delegated prefixes
- Integration with DHCPv6 client for dynamic reconfiguration
- Firewall rule automation for tunnel interfaces

This **userland integration gap** defines the OPNsense plugin development opportunity.

### 5.2 Interface and Tunnel Management

#### 5.2.1 gif Interface Usage: Generic Tunnel Interface for IPv4-in-IPv6

FreeBSD's **`gif` (Generic Interface)** provides **multi-protocol tunneling**:

| Mode | Protocol | Use Case |
|------|----------|----------|
| IPIP | IPv4-in-IPv4 | Legacy compatibility |
| IPIP6 | IPv4-in-IPv6 | **DS-LITE, MAP-E** |
| IP6IP6 | IPv6-in-IPv6 | IPv6 tunneling |

For MAP-E, the **dedicated `map` interface** (FreeBSD 14.0+) provides optimized handling; for DS-LITE, **`gif` in IPIP6 mode** remains appropriate.

#### 5.2.2 Interface Creation: Dynamic gif Interface Instantiation

**Dynamic interface lifecycle** for event-driven configuration:

```bash
# Creation
ifconfig gif0 create

# Configuration
ifconfig gif0 tunnel <local_ipv6> <aftr_ipv6>
ifconfig gif0 inet <private_ipv4> <aftr_ipv4> netmask 255.255.255.255

# Integration
route add -net default -interface gif0
```

OPNsense plugin integration: **hook into DHCPv6-PD events** for automatic creation, **monitor prefix changes** for reconfiguration, **cleanup on service disable**.

#### 5.2.3 Address Assignment: IPv4 Private Address on Tunnel Endpoint

| Protocol | IPv4 Address Source | Assignment Method |
|----------|---------------------|-------------------|
| MAP-E | Algorithmic from delegated prefix | Kernel `map` interface auto-configuration |
| DS-LITE | RFC 6333 standard (192.0.0.0/29) | Static `gif` interface configuration |

#### 5.2.4 Peer Address Configuration: AFTR IPv6 Address as Tunnel Destination

**AFTR address sources**:
- **MAP-E**: Prefix-derived calculation or static configuration
- **DS-LITE**: DHCPv6 Option 64, static configuration, or DNS resolution

### 5.3 DHCPv6 Prefix Delegation Handling

#### 5.3.1 Delegated Prefix Storage: `/tmp/<interfacename>_prefixv6` File Location

OPNsense's **dhcp6c client** stores delegated prefixes in:

```
/tmp/wan6_prefixv6          # Primary WAN6 prefix
/tmp/wan6_1_prefixv6        # Secondary prefix (if multiple)
```

File format: **plain text**, single line with prefix in standard notation (e.g., `240b:10:abcd:ef00::/40`) .

#### 5.3.2 Prefix Monitoring: Tracking /40 Delegation from NTT

**Monitoring strategies**:

| Approach | Mechanism | Responsiveness | Resource Impact |
|----------|-----------|--------------|---------------|
| File polling | Periodic `/tmp/*_prefixv6` check | 1-30 second delay | Low CPU, disk I/O |
| inotify | Filesystem event monitoring | Near-instant | Kernel event queue |
| dhcp6c hooks | Script execution on delegation | Instant | Event-driven |

**Recommended**: **dhcp6c hooks** for production, with **file polling fallback** for compatibility.

#### 5.3.3 Parameter Extraction: Script-Based Parsing for MAP-E Calculation

**Extraction pipeline**:

1. **Read** `/tmp/wan6_prefixv6`
2. **Parse** prefix and length (handle compressed `::` notation)
3. **Validate** expected NTT prefix range (240b::/16, 2404::/16, etc.)
4. **Calculate** EA-bits, PSID, IPv4 prefix, AFTR address
5. **Output** structured configuration for interface setup

#### 5.3.4 dhcp6c Integration: Custom Script Hooks for Prefix Change Events

**Hook implementation** in `/var/etc/dhcp6c.conf`:

```
interface wan6 {
    send ia-pd 0;
    script "/usr/local/opnsense/scripts/map-e/prefix-change.sh";
}
```

The **hook script** receives environment variables with delegation details and triggers plugin reconfiguration through OPNsense's configuration API.

### 5.4 pf Firewall Integration

#### 5.4.1 map-e-portset Syntax: FreeBSD pf Extension for Port Set Handling

**Critical pf extension** for MAP-E NAT (FreeBSD 14.0+):

```pf
# MAP-E interface with PSID-based port constraint
nat on map0 from $lan_net to any -> (map0) map-e-portset 4/8/20
```

Syntax: `map-e-portset <offset>/<length>/<psid>`

| Component | Description |
|-----------|-------------|
| `offset` | PSID offset bits (reserved low ports) |
| `length` | PSID length bits |
| `psid` | Subscriber's PSID value |

This extension **enforces port range constraints at NAT time**, preventing source port selection outside allocated ranges .

#### 5.4.2 NAT Rules: Outbound NAT for MAP-E Interface

**Complete NAT configuration**:

```pf
# MAP-E: PSID-constrained NAT
nat on map0 from $lan_net to any -> (map0) map-e-portset 4/8/20

# DS-LITE: Standard NAT (AFTR handles port allocation)
nat on gif0 from $lan_net to any -> (gif0)
```

#### 5.4.3 State Tracking: Connection State for Encapsulated Flows

**pf stateful inspection** applies to decapsulated IPv4 traffic:

- **Outbound**: State created on first packet, return traffic allowed
- **Inbound**: Default deny; explicit pass rules for published services
- **Encapsulation state**: Separate tracking for outer IPv6 tunnel flows

#### 5.4.4 Policy Configuration: Allow Rules for Tunnel-Established Traffic

**Typical policy structure**:

```pf
# Allow established connections
pass in quick on map0 from any to any keep state

# Allow LAN to tunnel
pass in quick on $lan_if from $lan_net to any route-to map0

# Block incoming to tunnel interface by default
block in on map0
```

## 6. OPNsense Plugin Architecture Design

### 6.1 Plugin Structure and Components

#### 6.1.1 Model-View-Controller (MVC) Framework: Standard OPNsense Plugin Pattern

OPNsense plugins follow **established MVC architecture**:

| Layer | Responsibility | Implementation |
|-------|---------------|----------------|
| **Model** | Data structures, validation, persistence | PHP classes extending `BaseModel` |
| **View** | Web interface forms, status display | Volt templates (`.volt`) |
| **Controller** | User action handling, service orchestration | PHP classes extending `IndexController` |

#### 6.1.2 Configuration Models: MAP-E and DS-LITE Parameter Storage

**Core model structure**:

```php
// MAP-E configuration
class MAP_E extends BaseModel {
    public $enabled;           // Boolean
    public $mode;              // 'auto' | 'manual'
    public $isp_profile;       // 'v6plus' | 'ocn' | 'custom'
    public $ipv6_prefix;       // Delegated prefix (read-only, auto-detected)
    public $ipv4_prefix;       // Calculated or manual
    public $aftr_address;      // Calculated or manual
    public $ea_length;         // Embedded Address bit length
    public $psid_length;       // PSID bit length
    public $psid_offset;       // PSID offset bits
    public $psid_value;        // Calculated PSID
    public $mtu;               // Interface MTU (default 1460)
    public $mss_clamp;         // TCP MSS clamp (default 1420)
}

// DS-LITE configuration  
class DS_LITE extends BaseModel {
    public $enabled;
    public $aftr_discovery;    // 'dhcp6' | 'static' | 'dns'
    public $aftr_address;      // Static or resolved address
    public $aftr_fqdn;         // For DNS-based discovery
    public $mtu;               // Interface MTU
}
```

#### 6.1.3 UI Forms: Web Interface for Protocol Selection and Parameter Input

**Progressive disclosure design**:

| Mode | Displayed Options | User Expertise |
|------|-----------------|--------------|
| **Simple** | ISP profile selection only | Home user |
| **Standard** | Profile + basic overrides (MTU, MSS) | Power user |
| **Advanced** | All parameters editable | Network engineer |

**Key UI elements**:
- **ISP profile selector** with regional AFTR database
- **Prefix status display** showing detected delegation
- **Calculated parameters preview** with validation indicators
- **Connection test button** for immediate verification

#### 6.1.4 Service Hooks: Integration with Existing DHCPv6 and Interface Management

**Integration points**:

| OPNsense Service | Hook Mechanism | Plugin Action |
|-----------------|---------------|-------------|
| dhcp6c | `script` directive in generated config | Prefix change notification |
| netifd | Interface state events | Tunnel create/destroy/reconfigure |
| pf | Anchor injection | Dynamic firewall rules |
| Web GUI | MVC controller actions | Configuration persistence |

### 6.2 Configuration Workflow

#### 6.2.1 Protocol Selection: MAP-E vs. DS-LITE Mode

**Selection logic**:

1. **Auto-detect**: Analyze delegated prefix characteristics, ISP hints
2. **Manual selection**: User explicitly chooses protocol
3. **Profile-driven**: ISP profile implies protocol (v6plus → MAP-E, Transix → DS-LITE)

#### 6.2.2 Automatic Parameter Detection: Prefix-Based AFTR Calculation for NTT

**Auto-detection pipeline**:

```
DHCPv6-PD prefix acquired
    ↓
Parse prefix (validate NTT range)
    ↓
Apply ISP-specific calculation rules
    ↓
Extract: IPv4 prefix, PSID, AFTR address, EA/PSID parameters
    ↓
Validate consistency (checksum-style verification)
    ↓
Populate configuration model
    ↓
Trigger interface creation
```

#### 6.2.3 Manual Parameter Override: Advanced Configuration for Non-NTT Deployments

**Override capabilities**:
- Direct EA-bit length, PSID length/offset entry
- Static AFTR address specification
- Custom IPv4 prefix assignment
- Non-standard MTU/MSS values

#### 6.2.4 Validation: Parameter Consistency and Range Checking

**Validation rules**:

| Parameter | Valid Range | Cross-Check |
|-----------|-------------|-------------|
| EA length | 0-48 bits | EA = (32 - IPv4 prefix len) + PSID len |
| PSID length | 0-16 bits | 2^PSID len ≤ ports available |
| PSID offset | 0-15 bits | Offset + PSID len ≤ 16 |
| IPv4 prefix | Valid unicast | Matches derived from EA-bits |
| AFTR address | Valid IPv6 unicast | Reachable via IPv6 path |

### 6.3 Runtime Implementation

#### 6.3.1 Interface Creation Hook: gif Interface Setup on WAN6 Prefix Delegation

**Event-driven interface management**:

| Event | Action | Implementation |
|-------|--------|---------------|
| WAN6 prefix delegated | Create tunnel interface | `ifconfig map0 create` (MAP-E) or `ifconfig gif0 create` (DS-LITE) |
| Prefix changed | Reconfigure interface | Update tunnel endpoints, recalculate parameters |
| Prefix released | Destroy interface | `ifconfig map0 destroy`, remove routes/firewall rules |
| Service disabled | Cleanup | Full interface and rule removal |

#### 6.3.2 Parameter Calculation Engine: NTT /40 Prefix to MAP-E Parameter Conversion

**Calculation implementation** (Python/PHP pseudocode):

```python
def calculate_map_e_params(ipv6_prefix: str, isp_profile: str) -> dict:
    """
    Calculate MAP-E parameters from delegated IPv6 prefix.
    NTT v6plus profile implementation.
    """
    # Parse prefix to 128-bit integer
    prefix_int = ipv6_to_int(ipv6_prefix)
    prefix_len = parse_prefix_length(ipv6_prefix)
    
    # Apply ISP-specific rules
    if isp_profile == 'v6plus':
        rule_ipv6_prefix_len = 31      # Observed NTT value
        ea_bit_len = 25                # Embedded Address bits
        ipv4_prefix_len = 15           # Shared IPv4 prefix
        psid_len = 8                   # Port Set ID bits
        psid_offset = 4                # Reserved low ports
    
    # Extract EA-bits from appropriate position
    ea_bits = extract_bits(prefix_int, rule_ipv6_prefix_len, ea_bit_len)
    
    # Partition EA-bits: IPv4 suffix + PSID
    ipv4_suffix_len = 32 - ipv4_prefix_len
    ipv4_suffix = ea_bits >> psid_len
    psid = ea_bits & ((1 << psid_len) - 1)
    
    # Construct complete IPv4 address
    rule_ipv4_prefix = get_rule_ipv4_prefix(isp_profile)  # Provider-specific
    ipv4_address = (rule_ipv4_prefix << ipv4_suffix_len) | ipv4_suffix
    
    # Calculate AFTR address (prefix-embedded scheme)
    aftr_address = calculate_aftr_address(prefix_int, isp_profile)
    
    # Calculate port range
    port_range = calculate_psid_ports(psid, psid_len, psid_offset)
    
    return {
        'ipv4_address': format_ipv4(ipv4_address),
        'ipv4_prefix_len': ipv4_suffix_len,
        'aftr_address': format_ipv6(aftr_address),
        'ea_length': ea_bit_len,
        'psid_length': psid_len,
        'psid_offset': psid_offset,
        'psid_value': psid,
        'port_range': port_range,
    }
```

#### 6.3.3 Tunnel Monitoring: Health Checking and Automatic Recovery

**Monitoring strategy**:

| Check | Method | Frequency | Failure Action |
|-------|--------|-----------|--------------|
| IPv6 connectivity | ICMPv6 echo to AFTR | Every 30s | Log warning, retry |
| IPv4 tunnel path | ICMPv4 echo through tunnel | Every 30s | Mark gateway down, failover |
| Prefix validity | Verify current prefix matches configured | On prefix change event | Recalculate and reconfigure |
| Port exhaustion | Track connection count vs. PSID range | Every 60s | Log alert if >80% utilized |

#### 6.3.4 Firewall Rule Injection: Dynamic pf Rules for MAP-E/DS-LITE Interface

**Rule generation template**:

```python
def generate_pf_rules(config: dict) -> str:
    interface = config['interface_name']
    lan_network = config['lan_network']
    psid_params = f"{config['psid_offset']}/{config['psid_length']}/{config['psid_value']}"
    
    rules = f"""
# Interface and routing
set skip on lo0
set skip on {interface}  # Let map interface handle its own state

# NAT with PSID constraint (MAP-E only)
nat on {interface} from {lan_network} to any -> ({interface}) map-e-portset {psid_params}

# MSS clamping
match on {interface} scrub (max-mss {config['mss_clamp']})

# Default deny incoming
block in on {interface}

# Allow established
pass in quick on {interface} from any to any keep state

# Outbound from LAN
pass in quick on {config['lan_interface']} from {lan_network} to any route-to {interface}
"""
    return rules
```

## 7. Code Implementation Examples

### 7.1 OpenWRT Reference Implementation

#### 7.1.1 MAP Interface Configuration Script

```bash
# /etc/config/network - OpenWRT MAP-E configuration

config interface 'wan6'
    option device 'eth1'
    option proto 'dhcpv6'
    option reqaddress 'try'
    option reqprefix 'auto'
    # For 1G plans without PD: explicit prefix required
    # option ip6prefix '240b:11:222:1000::/64'

config interface 'wan_map'
    option proto 'map'
    option maptype 'map-e'
    option tunlink 'wan6'
    
    # Calculated parameters from community tool
    option peeraddr '2404:9200:225:100::64'
    option ipaddr '106.73.2.34'
    option ip4prefixlen '32'
    option ip6prefix '240b:10::'
    option ip6prefixlen '31'
    option ealen '25'
    option psidlen '8'
    option offset '4'
    
    # Advanced options
    option legacymap '1'      # NTT compatibility mode
    option mtu '1460'
```

#### 7.1.2 DS-LITE Interface Configuration Script

```bash
# /etc/config/network - OpenWRT DS-LITE configuration

config interface 'wan6'
    option device 'eth1'
    option proto 'dhcpv6'
    option reqprefix 'auto'

config interface 'dslite'
    option proto 'dslite'
    option peeraddr '2001:c28:5:301::11'  # Transix AFTR
    option tunlink 'wan6'
    # option defaultroute '0'  # If managing routes manually
```

### 7.2 FreeBSD/OPNsense Implementation Patterns

#### 7.2.1 gif Interface Creation

```bash
#!/bin/sh
# OPNsense MAP-E/DS-LITE interface setup script

# MAP-E using native map interface (FreeBSD 14.0+)
setup_map_e() {
    local prefix="$1"
    local aftr="$2"
    local ipv4="$3"
    local psid_offset="$4"
    local psid_len="$5"
    local psid="$6"
    
    # Create map interface
    ifconfig map0 create 2>/dev/null || ifconfig map0 destroy && ifconfig map0 create
    
    # Configure with calculated parameters
    ifconfig map0 map-e \
        prefix "${prefix}" \
        aftr "${aftr}" \
        ipv4 "${ipv4}" \
        psid-offset "${psid_offset}" \
        psid-len "${psid_len}" \
        psid "${psid}"
    
    # Bring up
    ifconfig map0 up
}

# DS-LITE using gif interface
setup_ds_lite() {
    local local_v6="$1"
    local aftr_v6="$2"
    
    # Create gif interface
    ifconfig gif0 create 2>/dev/null || true
    
    # Configure tunnel
    ifconfig gif0 tunnel "${local_v6}" "${aftr_v6}"
    ifconfig gif0 inet 192.0.0.2 192.0.0.1 netmask 255.255.255.255
    
    # MTU optimization
    ifconfig gif0 mtu 1460
    
    # Bring up
    ifconfig gif0 up
}
```

#### 7.2.2 Route Injection

```bash
# Add default IPv4 route through tunnel
route add -net default -interface map0   # MAP-E
# OR
route add -net default -interface gif0   # DS-LITE

# Ensure IPv6 route remains for tunnel transport
route -6 add default -interface wan6
```

#### 7.2.3 pf NAT Configuration

```bash
# /etc/pf.conf.anchor.map-e - Dynamic pf rules for MAP-E

# Variables (populated by plugin)
map_if = "map0"
lan_net = "192.168.0.0/24"
psid_params = "4/8/20"  # offset/length/value

# NAT with PSID constraint
nat on $map_if from $lan_net to any -> ($map_if) map-e-portset $psid_params

# MSS clamping for TCP
match on $map_if scrub (max-mss 1420)

# State management
pass in quick on $map_if from any to any keep state
pass out quick on $map_if from any to any keep state
```

### 7.3 Parameter Calculation Logic

#### 7.3.1 NTT /40 Prefix Parsing

##### 7.3.1.1 Extract User IPv6 Prefix: First 40 Bits of Delegated Prefix

The **/40 prefix boundary** is significant for NTT MAP-E because it aligns with the provider's regional aggregation structure. Extraction involves:

```python
def extract_user_prefix(delegated_prefix: str) -> str:
    """
    Extract /40 user prefix from potentially longer delegation.
    NTT may delegate /48 or /56; we need consistent /40 for calculation.
    """
    import ipaddress
    
    network = ipaddress.ip_network(delegated_prefix, strict=False)
    
    # Truncate to /40 if longer
    if network.prefixlen > 40:
        # Extract first 40 bits
        network_int = int(network.network_address)
        mask = (0xFFFFFFFFFFFFFFFF << (128 - 40)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        user_prefix_int = network_int & mask
        user_prefix = ipaddress.IPv6Address(user_prefix_int)
        return f"{user_prefix}/40"
    
    return str(network.supernet(new_prefix=40)) if network.prefixlen < 40 else str(network)
```

##### 7.3.1.2 AFTR Address Derivation: Embedded Addressing Scheme

NTT's **prefix-embedded AFTR addressing** constructs the AFTR address from specific bits of the delegated prefix:

```python
def derive_ntt_aftr(user_prefix_40: str) -> str:
    """
    Derive AFTR address from /40 user prefix.
    Based on community reverse-engineering of NTT addressing.
    """
    import ipaddress
    
    prefix = ipaddress.ip_network(user_prefix_40)
    prefix_int = int(prefix.network_address)
    
    # NTT AFTR construction: specific bits from prefix + fixed suffix
    # Example observed pattern (may vary by region):
    # AFTR = [prefix bits 0-31]:[fixed 0x9200]:[prefix bits 32-39]:[fixed 0x100]::64
    
    # This is illustrative; actual NTT scheme requires validation
    high_bits = (prefix_int >> 96) & 0xFFFFFFFF  # First 32 bits
    low_bits = (prefix_int >> 88) & 0xFF         # Bits 32-39
    
    aftr_int = (high_bits << 96) | (0x9200 << 80) | (low_bits << 72) | (0x100 << 64)
    aftr = ipaddress.IPv6Address(aftr_int)
    
    return str(aftr)
```

##### 7.3.1.3 IPv4 Prefix Extraction: Algorithmic Mapping from IPv6 Prefix

```python
def extract_ipv4_prefix(user_prefix_40: str, ea_len: int = 25, 
                        ipv4_prefix_len: int = 15, psid_len: int = 8) -> tuple:
    """
    Extract IPv4 address and PSID from /40 prefix using EA-bit algorithm.
    """
    import ipaddress
    
    prefix = ipaddress.ip_network(user_prefix_40)
    prefix_int = int(prefix.network_address)
    
    # EA-bits start after Rule IPv6 Prefix (assumed /31 for NTT v6plus)
    rule_prefix_len = 31
    ea_start = 128 - rule_prefix_len - ea_len
    
    # Extract EA-bits
    ea_mask = (1 << ea_len) - 1
    ea_bits = (prefix_int >> ea_start) & ea_mask
    
    # Partition: IPv4 suffix (high bits) + PSID (low bits)
    ipv4_suffix_len = 32 - ipv4_prefix_len
    ipv4_suffix = ea_bits >> psid_len
    psid = ea_bits & ((1 << psid_len) - 1)
    
    # NTT's Rule IPv4 Prefix (observed: 153.240.0.0/15 for some regions)
    rule_ipv4_prefix = 0x99F00000  # 153.240.0.0
    
    ipv4_addr_int = (rule_ipv4_prefix & (0xFFFFFFFF << ipv4_suffix_len)) | ipv4_suffix
    ipv4_addr = ipaddress.IPv4Address(ipv4_addr_int)
    
    return (str(ipv4_addr), psid)
```

##### 7.3.1.4 PSID Calculation: Port Range Determination

```python
def calculate_psid_ports(psid: int, psid_len: int, psid_offset: int) -> list:
    """
    Calculate port ranges for given PSID parameters.
    Returns list of (start, end) tuples for contiguous ranges.
    """
    ports_per_psid = 1 << (16 - psid_offset - psid_len)
    base_port = (psid << (16 - psid_offset - psid_len)) | (1 << psid_offset)
    
    # For offset > 0, ports are non-contiguous
    # Simplified: return single range for offset=0
    # Full implementation handles distributed ranges
    
    if psid_offset == 0:
        return [(base_port, base_port + ports_per_psid - 1)]
    
    # Non-contiguous case: multiple ranges
    ranges = []
    for i in range(0, 1 << psid_offset, 1 << (16 - psid_len - psid_offset)):
        start = base_port + i
        end = start + ports_per_psid - 1
        ranges.append((start, end))
    
    return ranges
```

#### 7.3.2 Reference Implementation (Python/Shell)

##### 7.3.2.1 Prefix String Parsing: IPv6 Address to Binary Conversion

```python
#!/usr/bin/env python3
"""
NTT MAP-E Parameter Calculator
Reference implementation for OPNsense plugin
"""

import ipaddress
import sys
from dataclasses import dataclass

@dataclass
class MAPEParameters:
    ipv4_address: str
    ipv4_prefix_len: int
    aftr_address: str
    ea_length: int
    psid_length: int
    psid_offset: int
    psid_value: int
    port_ranges: list

def ipv6_to_int(addr_str: str) -> int:
    """Convert IPv6 address string to 128-bit integer."""
    return int(ipaddress.ip_address(addr_str))

def int_to_ipv6(addr_int: int) -> str:
    """Convert 128-bit integer to IPv6 address string."""
    return str(ipaddress.ip_address(addr_int))

def parse_delegated_prefix(prefix_str: str) -> tuple:
    """
    Parse delegated prefix string to network address and length.
    Handles compressed (::) notation.
    """
    network = ipaddress.ip_network(prefix_str, strict=False)
    return (int(network.network_address), network.prefixlen)

def calculate_ntt_v6plus_params(delegated_prefix: str) -> MAPEParameters:
    """
    Calculate MAP-E parameters for NTT v6plus service.
    Based on community-observed deployment characteristics.
    """
    # NTT v6plus observed parameters (validate against your deployment)
    RULE_IPV6_PREFIX_LEN = 31
    EA_LENGTH = 25
    IPV4_PREFIX_LEN = 15
    PSID_LENGTH = 8
    PSID_OFFSET = 4
    RULE_IPV4_PREFIX = 0x99F00000  # 153.240.0.0/15 - verify for your region
    
    prefix_int, prefix_len = parse_delegated_prefix(delegated_prefix)
    
    # Normalize to /40 for calculation
    if prefix_len > 40:
        prefix_int &= (0xFFFFFFFFFFFFFFFF << (128 - 40))
        prefix_len = 40
    
    # Extract EA-bits
    ea_start_bit = 128 - RULE_IPV6_PREFIX_LEN - EA_LENGTH
    ea_mask = (1 << EA_LENGTH) - 1
    ea_bits = (prefix_int >> ea_start_bit) & ea_mask
    
    # Partition EA-bits
    ipv4_suffix_len = 32 - IPV4_PREFIX_LEN
    ipv4_suffix = ea_bits >> PSID_LENGTH
    psid = ea_bits & ((1 << PSID_LENGTH) - 1)
    
    # Construct IPv4 address
    ipv4_addr_int = (RULE_IPV4_PREFIX & (0xFFFFFFFF << ipv4_suffix_len)) | ipv4_suffix
    
    # Derive AFTR (simplified - actual NTT scheme may vary)
    aftr_high = (prefix_int >> 96) & 0xFFFFFFFF
    aftr_low = (prefix_int >> 88) & 0xFF
    aftr_int = (aftr_high << 96) | (0x9200 << 80) | (aftr_low << 72) | (0x100 << 64)
    
    # Calculate port ranges
    ports_per_psid = 1 << (16 - PSID_OFFSET - PSID_LENGTH)
    port_ranges = []
    for group in range(16):  # Simplified for offset=4
        base = (psid << 4) + group * (1 << 12) + (1 << PSID_OFFSET)
        port_ranges.append((base, base + ports_per_psid - 1))
    
    return MAPEParameters(
        ipv4_address=str(ipaddress.IPv4Address(ipv4_addr_int)),
        ipv4_prefix_len=ipv4_suffix_len,
        aftr_address=int_to_ipv6(aftr_int),
        ea_length=EA_LENGTH,
        psid_length=PSID_LENGTH,
        psid_offset=PSID_OFFSET,
        psid_value=psid,
        port_ranges=port_ranges
    )

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <delegated-ipv6-prefix>")
        sys.exit(1)
    
    params = calculate_ntt_v6plus_params(sys.argv[1])
    print(f"IPv4 Address: {params.ipv4_address}/{params.ipv4_prefix_len}")
    print(f"AFTR Address: {params.aftr_address}")
    print(f"EA Length: {params.ea_length}")
    print(f"PSID: {params.psid_value} (length={params.psid_length}, offset={params.psid_offset})")
    print(f"Port Ranges: {params.port_ranges}")
```

##### 7.3.2.2 Bit Field Extraction: EA-bits, PSID-bits per RFC 7597

The **RFC 7597 bit field structure** for MAP-E:

```
IPv6 Address (128 bits):
[Rule IPv6 Prefix (variable)] [EA-bits (variable)] [subnet ID (variable)] [interface ID (64 bits)]

EA-bits partition:
[IPv4 address suffix (32 - IPv4_prefix_len bits)] [PSID (PSID_len bits)]
```

**Extraction implementation**:

```python
def extract_map_e_fields(ipv6_int: int, rule_v6_len: int, ea_len: int,
                         ipv4_prefix_len: int, psid_len: int) -> dict:
    """
    Extract MAP-E fields from IPv6 address per RFC 7597.
    """
    # EA-bits position: after Rule IPv6 Prefix
    ea_start = 128 - rule_v6_len - ea_len
    
    # Extract EA-bits
    ea_mask = (1 << ea_len) - 1
    ea_bits = (ipv6_int >> ea_start) & ea_mask
    
    # Partition EA-bits
    ipv4_suffix_len = 32 - ipv4_prefix_len
    psid_mask = (1 << psid_len) - 1
    
    ipv4_suffix = ea_bits >> psid_len
    psid = ea_bits & psid_mask
    
    return {
        'ea_bits': ea_bits,
        'ipv4_suffix': ipv4_suffix,
        'psid': psid,
        'ipv4_suffix_len': ipv4_suffix_len
    }
```

##### 7.3.2.3 Validation: Parameter Range and Consistency Checks

```python
def validate_mape_params(params: MAPEParameters) -> list:
    """
    Validate calculated MAP-E parameters.
    Returns list of error messages (empty if valid).
    """
    errors = []
    
    # EA length consistency
    expected_ea = (32 - params.ipv4_prefix_len) + params.psid_length
    if params.ea_length != expected_ea:
        errors.append(f"EA length {params.ea_length} != expected {expected_ea}")
    
    # PSID range
    max_psid = (1 << params.psid_length) - 1
    if params.psid_value > max_psid:
        errors.append(f"PSID {params.psid_value} exceeds maximum {max_psid}")
    
    # PSID offset + length constraint
    if params.psid_offset + params.psid_length > 16:
        errors.append(f"PSID offset+length {params.psid_offset}+{params.psid_length} > 16")
    
    # IPv4 address validity
    try:
        ipaddress.IPv4Address(params.ipv4_address)
    except ValueError as e:
        errors.append(f"Invalid IPv4 address: {e}")
    
    # AFTR address validity
    try:
        ipaddress.IPv6Address(params.aftr_address)
    except ValueError as e:
        errors.append(f"Invalid AFTR address: {e}")
    
    # Port range validity
    for start, end in params.port_ranges:
        if start < 0 or end > 65535 or start > end:
            errors.append(f"Invalid port range {start}-{end}")
    
    return errors
```

## 8. NTT Network-Specific Implementation Details

### 8.1 Service Identification

#### 8.1.1 "v6plus" Service Branding: NTT MAP-E Service Name

**"v6plus"** is the commercial brand for NTT's MAP-E service, operated through **JPIX (Japan Internet Exchange)** . Service identification characteristics:

- **Protocol**: MAP-E (RFC 7597)
- **Marketing**: "IPv4 over IPv6" or "v6plus compatible"
- **CPE indication**: Routers display "v6plus" mode or MAP-E configuration
- **Support documentation**: NTT East/West provide setup guides for major router brands

#### 8.1.2 "Transix" Alternative: DS-LITE Service for Some Regions

**"Transix"** is Internet Multifeed Co.'s DS-LITE service, available as alternative to v6plus:

| Characteristic | v6plus (MAP-E) | Transix (DS-LITE) |
|---------------|--------------|-------------------|
| Protocol | MAP-E | DS-LITE |
| State | Stateless | Stateful |
| Port allocation | Fixed PSID-based | Dynamic NAT44 |
| AFTR discovery | Prefix-derived | Static/DHCPv6 Option 64 |
| Typical AFTR | 2404:9200::/32 range | 2001:c28::/32 range |

#### 8.1.3 Plan Differentiation: 1G vs. 10G Prefix Delegation Behavior

| Plan | Historical Behavior | Current Behavior | PD Requirement |
|------|-------------------|----------------|---------------|
| 1G (no Hikari Denwa) | /64, no PD | /56 with PD | None |
| 1G (with Hikari Denwa) | /56 with PD | /56 with PD | Hikari Denwa subscription |
| 10G | /56 or /48 with PD | /56 to /40 with PD | None |

### 8.2 AFTR Address Discovery

#### 8.2.1 Static Configuration: Known AFTR Addresses per Region

**Community-documented AFTR addresses** (verify current validity):

| Region/Service | AFTR Address | Notes |
|---------------|-------------|-------|
| NTT East v6plus | 2404:9200:225:100::64 | Observed value, may vary |
| NTT West v6plus | 2404:9200:225:100::64 | Possible anycast |
| Transix | 2001:c28:5:301::11 | Static configuration |
| OCN Virtual Connect | 2404:8e00::/32 range | MAP-E variant |

#### 8.2.2 DHCPv6 Option 64: Dynamic AFTR Address Learning (Limited NTT Support)

**DHCPv6 Option 64 (AFTR_NAME)** provides standards-based dynamic discovery per RFC 6334. However, **NTT's deployment makes limited use of this mechanism** for MAP-E, preferring prefix-embedded addressing. DS-LITE deployments show more consistent Option 64 support.

For OPNsense plugin: **implement Option 64 parsing as fallback**, with static configuration as primary method for NTT services.

#### 8.2.3 Prefix-Embedded Addressing: AFTR Derived from Delegated /40

NTT's **prefix-embedded AFTR scheme** constructs the AFTR address from specific bits of the customer's /40 delegated prefix:

```
AFTR IPv6 address construction (observed pattern):
[Prefix bits 0-31] : 0x9200 : [Prefix bits 32-39] : 0x100 :: 64
```

This scheme enables **automatic AFTR determination** without additional protocol exchanges, aligning with MAP-E's stateless philosophy.

### 8.3 Known Implementation Quirks

#### 8.3.1 Prefix Delegation Timing: Delayed Prefix Availability Post-Connection

**Observed behavior**: DHCPv6-PD may not immediately provide usable prefix after WAN6 link establishment. Recommended handling:

- **Implement retry logic** with exponential backoff
- **Monitor prefix file appearance** with timeout (30-60 seconds typical)
- **Provide clear status indication** of prefix acquisition progress

#### 8.3.2 MTU Path Issues: Fragmentation Handling for Encapsulated Traffic

**Common problems**:
- **PMTUD black holes**: ICMP filtering prevents MTU discovery
- **MSS mismatch**: Default 1460 MTU with 1460 MSS causes fragmentation
- **UDP applications**: No automatic size reduction, manual configuration required

**Mitigation**: Conservative **1420-byte MSS clamping** as default, with user-adjustable override.

#### 8.3.3 DNS Resolution: IPv4 DNS Through Tunnel vs. IPv6 Native DNS

**Architectural decision**: DNS queries can use:
- **IPv6 native DNS**: Preferred, avoids tunnel overhead
- **IPv4 DNS through tunnel**: Required for some ISP-mandated resolvers

**Recommendation**: Implement **split DNS configuration**, preferring IPv6 resolvers with IPv4 fallback through tunnel.

## 9. Testing and Validation

### 9.1 Connectivity Testing

#### 9.1.1 IPv6 Native Connectivity: Verify Prefix Delegation

**Validation checklist**:

| Test | Command/Method | Expected Result |
|------|-------------|---------------|
| Prefix file exists | `ls /tmp/wan6_prefixv6` | File present with valid prefix |
| IPv6 address assigned | `ifconfig wan6` | Global scope address from delegated prefix |
| IPv6 routing functional | `ping6 -c 3 2001:4860:4860::8888` | Successful echo replies |
| PD validation | `cat /tmp/wan6_prefixv6` | Matches expected prefix range |

#### 9.1.2 IPv4 Through Tunnel: Verify Encapsulated Path to AFTR

| Test | Command/Method | Expected Result |
|------|-------------|---------------|
| Tunnel interface up | `ifconfig map0` or `ifconfig gif0` | Interface UP with correct addresses |
| IPv4 route installed | `netstat -rn -f inet` | Default route via tunnel interface |
| AFTR reachability | `ping6 -c 3 <aftr_address>` | Successful from WAN6 |
| IPv4 connectivity | `ping -c 3 8.8.8.8` | Successful through tunnel |
| Traceroute validation | `traceroute 8.8.8.8` | Shows tunnel path |

#### 9.1.3 Port Range Validation: Confirm PSID-Based Port Allocation

| Test | Method | Validation |
|------|--------|-----------|
| Connection source ports | `sockstat -4` or packet capture | Ports within allocated PSID range |
| Port exhaustion test | Concurrent connection generator | Fails gracefully at limit, no crashes |
| Application compatibility | P2P, gaming, VoIP tests | Functional within port constraints |

### 9.2 Performance Benchmarking

#### 9.2.1 Throughput Measurement: Encapsulation Overhead Impact

**Expected performance characteristics**:

| Metric | Native IPv6 | MAP-E/DS-LITE | Notes |
|--------|-----------|---------------|-------|
| Maximum throughput | Line rate | ~95-98% of line rate | 40-byte header overhead |
| CPU utilization | Baseline | +10-30% | Encapsulation processing |
| Small packet performance | Baseline | -5-15% | Header overhead proportion |

#### 9.2.2 Latency Analysis: Tunnel Path vs. Native IPv6

**Typical observations**:
- **Added latency**: 0.5-2ms for tunnel processing at CPE and AFTR
- **Geographic impact**: AFTR location affects path; anycast helps
- **Jitter**: Minimal increase with proper QoS

#### 9.2.3 MTU Optimization: Path MTU Discovery Effectiveness

**Validation approach**:
1. **Baseline test**: `ping -M do -s 1472 <target>` (1472 = 1500 - 20 IP - 8 ICMP)
2. **Through tunnel**: `ping -M do -s 1432 <target>` (accounting for 40-byte IPv6 header)
3. **Verify PMTUD**: Monitor with tcpdump for ICMP Fragmentation Needed

## 10. Community Resources and References

### 10.1 Open Source Implementations

#### 10.1.1 OpenWRT MAP Package: Linux netifd Integration

The **OpenWRT `map` package** provides reference implementation for Linux-based MAP-E/MAP-T deployment:

- **Source**: `git.openwrt.org` feed packages
- **Key files**: `map.sh` protocol handler, `mapcalc` utility
- **Integration**: netifd network daemon, UCI configuration

#### 10.1.2 OpenWRT DS-LITE Package: Tunnel Management Scripts

The **`ds-lite` package** demonstrates simplified stateful tunnel implementation:

- **Protocol handler**: `dslite.sh`
- **Configuration**: Minimal parameter set (peeraddr, tunlink)
- **NAT handling**: Explicit disablement for pure B4 operation

#### 10.1.3 FreeBSD MAP-E Commit: Kernel-Level Implementation Reference

**Commit `2aa21096c7349390f22aa5d06b373a575baed1b4`** (FreeBSD 14.0) :

- **Added**: `map` interface driver, `map-e-portset` pf extension
- **Location**: `sys/net/if_map.c`, `sys/netpfil/pf/pf_nat.c`
- **Documentation**: `man 4 map` (FreeBSD 14.0+)

### 10.2 Documentation and Standards

#### 10.2.1 RFC 7597: MAP-E Specification

**"Mapping of Address and Port with Encapsulation (MAP-E)"** (July 2015)

- **Core specification**: Stateless algorithmic mapping, encapsulation format
- **Key sections**: Section 5 (address mapping algorithm), Section 6 (BR operation)
- **Errata**: Check for updates affecting implementation details

#### 10.2.2 RFC 6333: DS-LITE Specification

**"Dual-Stack Lite Broadband Deployments Following IPv4 Exhaustion"** (August 2011)

- **Architecture**: B4 and AFTR elements, tunneling requirements
- **Configuration**: DHCPv6 Option 64, static setup
- **Operational considerations**: NAT44, logging, scaling

#### 10.2.3 RFC 8585: IPv6 Transition CE Router Requirements

**"Requirements for IPv6 Customer Edge Routers to Support IPv4-as-a-Service"** (May 2019)

- **CPE requirements**: MAP-E, DS-LITE, and other transition technologies
- **Management interface**: Configuration, monitoring, diagnostics
- **Interoperability**: Multi-vendor deployment considerations

### 10.3 Community Tools

#### 10.3.1 NTT MAP-E Parameter Calculators: Web-Based and Script Implementations

| Tool | URL/Location | Features |
|------|-----------|----------|
| Web calculator | ipv4.web.fc2.com | Interactive, complete parameter output |
| OpenWRT community | github.com/fakemanhk/openwrt-jp-ipoe | Documented configurations, scripts |
| Python implementations | Various GitHub repositories | Programmatic access, validation |

#### 10.3.2 Configuration Generators: ISP-Specific Setup Assistants

Emerging tools provide **profile-based configuration generation**:

- **Input**: ISP selection, delegated prefix (optional)
- **Output**: Router-specific configuration (OpenWRT, OPNsense, etc.)
- **Validation**: Cross-check against known-good deployments

