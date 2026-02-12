# Another Betterthannothing VPN

Un'infrastruttura VPN usa e getta su AWS con superficie di attacco minima e automazione completa del ciclo di vita.

> **Lingue disponibili**: [English](README.md) | [Italiano (corrente)](README.it.md)

## Panoramica

`Another Betterthannothing VPN` crea un VPC AWS dedicato con un'istanza EC2 che esegue WireGuard VPN, gestibile interamente tramite CloudFormation e un singolo script Bash. L'infrastruttura supporta sia la modalità full-tunnel (tutto il traffico attraverso la VPN) che split-tunnel (solo il traffico VPC attraverso la VPN), con accesso sicuro tramite AWS Systems Manager (SSM) - nessuna esposizione SSH pubblica.

**Caratteristiche principali:**
- 🔒 **Sicuro per impostazione predefinita**: accesso solo SSM, nessuna esposizione SSH, IMDSv2 applicato
- 💰 **Costi trasparenti**: tutte le risorse taggate con `CostCenter` per un tracciamento accurato
- ⚡ **Distribuzione con un solo comando**: crea, configura e genera configurazioni client in un solo passaggio
- 🌍 **Supporto multi-regione**: distribuisci l'infrastruttura VPN in qualsiasi regione AWS
- 🔄 **Effimero**: progettato per casi d'uso temporanei, facile da creare e distruggere
- 🐧 **Compatibile con NixOS**: gestione automatica delle dipendenze per ambienti dichiarativi

## Indice

- [Sicurezza / Modello di Minaccia](#sicurezza--modello-di-minaccia)
- [Box di Calcolo Effimero](#box-di-calcolo-effimero)
- [Prerequisiti](#prerequisiti)
- [Avvio Rapido](#avvio-rapido)
- [Riferimento CLI](#riferimento-cli)
- [Comprendere i Parametri CIDR](#comprendere-i-parametri-cidr)
- [Supporto Elastic IP (EIP)](#supporto-elastic-ip-eip)
- [Best Practice di Sicurezza](#best-practice-di-sicurezza)
- [Considerazioni sui Costi](#considerazioni-sui-costi)
- [Esempi](#esempi)
- [Log di Esecuzione](#log-di-esecuzione)
- [Risoluzione dei Problemi](#risoluzione-dei-problemi)
- [Pulizia](#pulizia)

## Sicurezza / Modello di Minaccia

### L'Approccio "Meglio di Niente"

Questa VPN è progettata per **scenari temporanei a basso rischio** in cui hai bisogno di privacy di rete di base o accesso alle risorse AWS. **NON** è un sostituto per soluzioni VPN aziendali o servizi orientati alla privacy come Mullvad o ProtonVPN.

**Quando usare questa VPN:**
- ✅ Accesso alle risorse AWS in un VPC privato dal tuo laptop
- ✅ Ambienti di laboratorio temporanei per test e sviluppo
- ✅ Accesso rapido ai servizi interni durante i viaggi
- ✅ Esecuzione di carichi di lavoro di calcolo effimeri (vedi sotto)
- ✅ Apprendimento sull'infrastruttura VPN e WireGuard

**Quando NON usare questa VPN:**
- ❌ Protezione di dati o comunicazioni aziendali sensibili
- ❌ Elusione della censura in ambienti ostili (single point of failure)
- ❌ Carichi di lavoro di produzione a lungo termine che richiedono alta disponibilità
- ❌ Scenari che richiedono anonimato (l'account AWS è legato alla tua identità)
- ❌ Ambienti regolamentati per conformità (HIPAA, PCI-DSS, ecc.)


### Limitazioni e Rischi

**Limitazioni dell'Infrastruttura:**
- **Singolo punto di guasto**: un'istanza EC2, nessuna ridondanza
- **Nessuna protezione DDoS**: solo regole di Security Group di base
- **Collegamento all'account AWS**: tutto il traffico è associato al tuo account AWS
- **Interruzioni delle istanze Spot**: se usi `--spot`, l'istanza può essere terminata con 2 minuti di preavviso
- **Cambiamenti dell'IP pubblico**: fermare/avviare l'istanza cambia l'IP pubblico

**Considerazioni sulla Sicurezza:**
- **Fiducia in AWS**: ti stai fidando dell'infrastruttura AWS e della sicurezza del tuo account
- **Log CloudWatch**: i VPC Flow Logs (se abilitati) possono catturare metadati
- **Tracciamento dei costi**: tutte le risorse sono taggate con il nome del tuo stack
- **Gestione delle chiavi**: le chiavi private dei client sono memorizzate localmente sulla tua macchina

### Cosa Protegge Questa VPN

✅ **WiFi non crittografato**: crittografa il traffico su reti non affidabili (bar, aeroporti)  
✅ **Snooping di base**: previene l'osservazione casuale del tuo traffico  
✅ **Restrizioni basate su IP**: accedi a servizi che filtrano per indirizzo IP  
✅ **Accesso VPC**: accedi in modo sicuro alle risorse AWS private senza esporle pubblicamente

### Cosa Questa VPN NON Protegge

❌ **Avversari determinati**: attori a livello statale, attaccanti sofisticati  
❌ **AWS stesso**: AWS può vedere i metadati del tuo traffico e l'utilizzo delle risorse  
❌ **Compromissione dell'endpoint**: se il tuo laptop è compromesso, la VPN non aiuta  
❌ **Analisi del traffico**: i pattern di tempistica e volume potrebbero essere ancora osservabili

## Box di Calcolo Effimero

Un caso d'uso potente è trattare il server VPN come un **ambiente di calcolo temporaneo** per eseguire carichi di lavoro che necessitano:
- Un ambiente pulito e isolato
- Un indirizzo IP o una posizione geografica diversi
- Accesso ai servizi AWS dalla stessa regione (latenza inferiore, nessun costo di trasferimento dati)

### Esempio: Esecuzione di Container Docker

Una volta connesso alla VPN, puoi accedere all'istanza tramite SSM ed eseguire carichi di lavoro Docker:

```bash
# Apri una sessione SSM al server VPN
./another_betterthannothing_vpn.sh ssm --name my-vpn-stack

# All'interno dell'istanza, installa Docker
sudo dnf install -y docker
sudo systemctl start docker

# Esegui un web scraper temporaneo
sudo docker run --rm -it python:3.11 bash
pip install requests beautifulsoup4
python your_script.py

# Esegui un database per test
sudo docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=test postgres:15

# Accedi dal tuo laptop (attraverso il tunnel VPN)
psql -h 10.10.1.x -U postgres
```

### Esempio: Ambiente di Build Temporaneo

```bash
# Connettiti tramite SSM
./another_betterthannothing_vpn.sh ssm --name my-vpn-stack

# Installa strumenti di build
sudo dnf install -y gcc make git

# Clona e compila un progetto
git clone https://github.com/example/project.git
cd project
make

# Copia gli artefatti sul tuo laptop tramite S3 o SCP attraverso la VPN
```

### Accesso ai Servizi sul Server VPN

Per accedere ai servizi in esecuzione sul server VPN stesso (container Docker, Apache, database, ecc.) dal tuo client VPN, usa il flag `--reach-server` quando crei la VPN:

```bash
./another_betterthannothing_vpn.sh create --my-ip --reach-server
```

Questo aggiunge la subnet VPN (`10.99.0.0/24`) agli AllowedIPs del client, permettendoti di raggiungere il server a `10.99.0.1`.

**Importante:** I servizi devono fare bind su `0.0.0.0` o `10.99.0.1` per essere raggiungibili via VPN:

```bash
# All'interno del server VPN (via SSM)

# Docker: esponi su tutte le interfacce
sudo docker run -d -p 0.0.0.0:8080:80 nginx

# Oppure fai bind specificamente sull'interfaccia VPN
sudo docker run -d -p 10.99.0.1:8080:80 nginx

# Dal tuo laptop (connesso alla VPN)
curl http://10.99.0.1:8080
```

**Vantaggi:**
- 🧹 **Tabula rasa**: ambiente fresco ogni volta, nessuna dipendenza residua
- 💸 **Conveniente**: paghi solo per ciò che usi, distruggi quando hai finito
- 🔒 **Isolato**: separato dal tuo laptop, facile da cancellare
- ⚡ **Accesso AWS veloce**: accesso nella stessa regione a S3, RDS, ecc. senza costi di trasferimento dati


## Prerequisiti

Prima di utilizzare questo strumento, assicurati di avere installato quanto segue:

### 1. AWS CLI (v2 consigliata)

**Installazione:**
- **Linux**: `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install`
- **macOS**: `brew install awscli` o scarica da [AWS](https://aws.amazon.com/cli/)
- **Windows**: Scarica l'installer da [AWS](https://aws.amazon.com/cli/)

**Configurazione:**
```bash
aws configure
# Inserisci il tuo AWS Access Key ID, Secret Access Key, regione predefinita e formato di output
```

**Permessi IAM Richiesti:**
Le tue credenziali AWS devono avere permessi per:
- `cloudformation:CreateStack`, `DeleteStack`, `DescribeStacks`, `ListStacks`
- `ec2:DescribeInstances`, `DescribeImages`, `StartInstances`, `StopInstances`
- `ssm:DescribeInstanceInformation`, `StartSession`, `SendCommand`
- `iam:PassRole` (per allegare il profilo dell'istanza)

### 2. AWS Systems Manager Session Manager Plugin

**Installazione:**
- **Linux**: [Guida all'installazione](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-linux)
- **macOS**: `brew install --cask session-manager-plugin`
- **Windows**: [Scarica l'installer](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-windows)

**Verifica l'installazione:**
```bash
session-manager-plugin
# Dovrebbe visualizzare le informazioni sull'utilizzo
```

### 3. jq (processore JSON)

**Installazione:**
- **Linux**: `sudo dnf install jq` o `sudo apt install jq`
- **macOS**: `brew install jq`
- **Windows**: Scarica dal [sito web jq](https://stedolan.github.io/jq/)

### 4. Client WireGuard (sui tuoi dispositivi)

**Installazione:**
- **Linux**: `sudo dnf install wireguard-tools` o `sudo apt install wireguard`
- **macOS**: Scarica dal [sito web WireGuard](https://www.wireguard.com/install/) o `brew install wireguard-tools`
- **Windows**: Scarica dal [sito web WireGuard](https://www.wireguard.com/install/)
- **iOS/Android**: Installa l'app WireGuard dall'App Store / Google Play

### Utenti NixOS

Se sei su NixOS, lo script rileverà automaticamente le dipendenze mancanti e creerà una shell temporanea con tutti i pacchetti richiesti. Nessuna installazione manuale necessaria!

## Avvio Rapido

### Creare una VPN (Modalità Split-Tunnel)

La modalità split-tunnel instrada solo il traffico VPC attraverso la VPN, lasciando il traffico internet sulla tua connessione locale:

```bash
# Crea VPN con restrizione IP rilevata automaticamente (più sicuro)
./another_betterthannothing_vpn.sh create --my-ip --mode split

# Oppure specifica il tuo IP manualmente
./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.42/32 --mode split

# CIDR VPC personalizzato (se il predefinito 10.10.0.0/16 è in conflitto con la tua rete)
./another_betterthannothing_vpn.sh create --my-ip --mode split --vpc-cidr 172.16.0.0/16
```

**Cosa succede:**
1. Crea uno stack CloudFormation con VPC, subnet, security group, ruolo IAM e istanza EC2
2. Attende che l'istanza sia pronta e che l'agente SSM si connetta
3. Installa e configura WireGuard sul server
4. Genera il file di configurazione del client
5. Visualizza le istruzioni di connessione

**Output:**
```
Creating stack 'abthn-vpn-20260201-a3f9' in region 'us-east-1'...
Stack creation complete!
Instance ready, bootstrapping VPN server...
VPN server configured successfully!

Client configuration saved to: ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-1.conf

Connection Instructions:
  Endpoint: 54.123.45.67:51820
  Mode: split-tunnel (only VPC traffic: 10.10.0.0/16)

To connect:
  1. Import the config file to your WireGuard client
  2. Activate the connection

To add more clients:
  ./another_betterthannothing_vpn.sh add-client --name abthn-vpn-20260201-a3f9
```


### Creare una VPN (Modalità Full-Tunnel)

La modalità full-tunnel instrada TUTTO il traffico attraverso la VPN:

```bash
# Crea VPN full-tunnel con restrizione IP
./another_betterthannothing_vpn.sh create --my-ip --mode full

# Usa istanze Spot per costi inferiori (possono essere interrotte)
./another_betterthannothing_vpn.sh create --my-ip --mode full --spot
```

### Importare la Configurazione nel Client WireGuard

**Linux/macOS:**
```bash
# Copia la configurazione nella directory WireGuard
sudo cp ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-1.conf /etc/wireguard/

# Avvia la VPN
sudo wg-quick up client-1

# Ferma la VPN
sudo wg-quick down client-1
```

**Windows/macOS GUI:**
1. Apri l'applicazione WireGuard
2. Clicca su "Import tunnel(s) from file"
3. Seleziona il file `.conf`
4. Clicca su "Activate"

**iOS/Android:**
1. Apri l'app WireGuard
2. Tocca "+" → "Create from file or archive"
3. Seleziona il file `.conf` (trasferisci tramite AirDrop, email, ecc.)
4. Tocca l'interruttore per connetterti

## Riferimento CLI

### Comandi

#### `create`

Crea un nuovo stack VPN con tutta l'infrastruttura e la configurazione.

```bash
./another_betterthannothing_vpn.sh create [opzioni]
```

**Opzioni:**
- `--region <regione>` - Regione AWS (predefinito: us-east-1)
- `--name <nome-stack>` - Nome dello stack (predefinito: generato automaticamente come `another-YYYYMMDD-xxxx`)
- `--mode <full|split>` - Modalità tunnel (predefinito: split)
  - `full`: Instrada tutto il traffico attraverso la VPN
  - `split`: Instrada solo il traffico VPC attraverso la VPN
- `--allowed-cidr <cidr>` - CIDR sorgente autorizzato a connettersi alla porta VPN (ripetibile, predefinito: 0.0.0.0/0)
- `--my-ip` - Rileva automaticamente e usa il tuo IP pubblico/32 (mutuamente esclusivo con --allowed-cidr)
- `--vpc-cidr <cidr>` - Blocco CIDR VPC (predefinito: 10.10.0.0/16, deve essere un intervallo privato RFC 1918)
- `--instance-type <tipo>` - Tipo di istanza EC2 (predefinito: t4g.nano)
- `--spot` - Usa istanze EC2 Spot per costi inferiori (possono essere interrotte)
- `--eip` - Alloca un Elastic IP per un indirizzo IP pubblico persistente
- `--reach-server` - Include la subnet del server VPN (10.99.0.0/24) negli AllowedIPs del client, permettendo ai client di raggiungere servizi in esecuzione sul server VPN stesso (es. container Docker)
- `--peer-type <host|router>` - Tipo di peer: `host` (predefinito) per client standard, `router` per site-to-site con subnet LAN
- `--router-subnet <cidr>` - Subnet LAN dietro il router peer (ripetibile, solo con `--peer-type router`)
- `--mtu <valore>` - Valore MTU personalizzato (predefinito: 1360)
- `--mss-clamping` - Abilita MSS clamping per connessioni TCP (utile per router peer)
- `--clients <n>` - Numero di configurazioni client iniziali da generare (predefinito: 1)
- `--output-dir <percorso>` - Directory di output per le configurazioni client (predefinito: ./another_betterthannothing_vpn_config)
- `--yes` - Salta i prompt di conferma

**Esempi:**
```bash
# Configurazione sicura minimale
./another_betterthannothing_vpn.sh create --my-ip

# Full-tunnel con regione personalizzata
./another_betterthannothing_vpn.sh create --my-ip --mode full --region eu-west-1

# Genera 3 configurazioni client alla creazione
./another_betterthannothing_vpn.sh create --my-ip --clients 3

# Usa istanza Spot per risparmiare sui costi
./another_betterthannothing_vpn.sh create --my-ip --spot

# CIDR VPC personalizzato per evitare conflitti
./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 172.16.0.0/16

# Crea VPN con Elastic IP (indirizzo IP persistente)
./another_betterthannothing_vpn.sh create --my-ip --eip

# Crea VPN con accesso al server stesso (per container Docker, ecc.)
./another_betterthannothing_vpn.sh create --my-ip --reach-server
```

#### `delete`

Elimina uno stack VPN e tutta l'infrastruttura associata.

```bash
./another_betterthannothing_vpn.sh delete --name <nome-stack> [opzioni]
```

**Opzioni:**
- `--region <regione>` - Regione AWS (predefinito: us-east-1)
- `--yes` - Salta il prompt di conferma

**Esempio:**
```bash
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

**Nota:** Questo elimina tutte le risorse AWS ma NON elimina i file di configurazione client locali.


#### `status`

Visualizza le informazioni di stato per uno stack VPN.

```bash
./another_betterthannothing_vpn.sh status --name <nome-stack> [opzioni]
```

**Opzioni:**
- `--region <regione>` - Regione AWS (predefinito: us-east-1)

**Esempio:**
```bash
./another_betterthannothing_vpn.sh status --name abthn-vpn-20260201-a3f9
```

**Output:**
```
Stack: abthn-vpn-20260201-a3f9
Status: CREATE_COMPLETE
Region: us-east-1
Instance ID: i-0123456789abcdef0
Instance State: running
Public IP: 54.123.45.67
VPC CIDR: 10.10.0.0/16
VPN Endpoint: 54.123.45.67:51820
Client Configs: 2
```

#### `list`

Elenca tutti gli stack VPN in una regione.

```bash
./another_betterthannothing_vpn.sh list [opzioni]
```

**Opzioni:**
- `--region <regione>` - Regione AWS (predefinito: us-east-1)

**Esempio:**
```bash
./another_betterthannothing_vpn.sh list --region us-east-1
```

**Output:**
```
Stack Name                  Status              Region      VPN Endpoint
abthn-vpn-20260201-a3f9      CREATE_COMPLETE     us-east-1   54.123.45.67:51820
abthn-vpn-20260201-b7k2      CREATE_COMPLETE     us-east-1   54.234.56.78:51820
```

#### `add-client`

Genera una nuova configurazione client per uno stack VPN esistente.

```bash
./another_betterthannothing_vpn.sh add-client --name <nome-stack> [opzioni]
```

**Opzioni:**
- `--region <regione>` - Regione AWS (predefinito: us-east-1)

**Esempio:**
```bash
./another_betterthannothing_vpn.sh add-client --name abthn-vpn-20260201-a3f9
```

**Output:**
```
Generating new client configuration...
Client configuration saved to: ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-2.conf

Connection Instructions:
  Endpoint: 54.123.45.67:51820
  Import the config file to your WireGuard client
```

#### `ssm`

Apri una sessione SSM interattiva al server VPN per risoluzione dei problemi o operazioni manuali.

```bash
./another_betterthannothing_vpn.sh ssm --name <nome-stack> [opzioni]
```

**Opzioni:**
- `--region <regione>` - Regione AWS (predefinito: us-east-1)

**Esempio:**
```bash
./another_betterthannothing_vpn.sh ssm --name abthn-vpn-20260201-a3f9
```

**All'interno della sessione:**
```bash
# Controlla lo stato di WireGuard
sudo wg show

# Visualizza i log di WireGuard
sudo journalctl -u wg-quick@wg0

# Controlla i peer connessi
sudo wg show wg0 peers

# Visualizza la configurazione del server
sudo cat /etc/wireguard/wg0.conf
```

#### `start` / `stop`

Avvia o ferma l'istanza EC2 (la VPN non sarà disponibile quando è fermata).

```bash
./another_betterthannothing_vpn.sh start --name <nome-stack>
./another_betterthannothing_vpn.sh stop --name <nome-stack>
```

**Nota:** Fermare e avviare l'istanza cambierà il suo indirizzo IP pubblico. Dovrai aggiornare le configurazioni client con il nuovo endpoint.


## Comprendere i Parametri CIDR

Il sistema utilizza **due parametri CIDR distinti** con scopi diversi. Comprendere la differenza è cruciale per una configurazione corretta.

### 1. VPC CIDR (`--vpc-cidr`)

**Scopo:** Definisce la rete privata interna per il VPC AWS.

**Predefinito:** `10.10.0.0/16`

**Utilizzato per:**
- Allocazione della subnet VPC
- Assegnazione dell'IP privato dell'istanza EC2
- Routing interno all'interno di AWS

**Quando personalizzare:**
- La tua rete locale o VPN aziendale usa `10.10.0.0/16` (conflitto)
- Hai bisogno di una dimensione di subnet diversa
- Stai connettendo più VPC e hai bisogno di intervalli non sovrapposti

**Valori validi:**
- Deve essere uno spazio di indirizzi privati RFC 1918:
  - `10.0.0.0/8` (10.0.0.0 - 10.255.255.255)
  - `172.16.0.0/12` (172.16.0.0 - 172.31.255.255)
  - `192.168.0.0/16` (192.168.0.0 - 192.168.255.255)
- La lunghezza del prefisso deve essere tra `/16` e `/28`

**Esempi:**
```bash
# Usa l'intervallo 172.16.x.x invece di 10.10.x.x
./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 172.16.0.0/16

# VPC più piccolo per un utilizzo minimo delle risorse
./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 192.168.100.0/24
```

### 2. CIDR Ingresso Consentito (`--allowed-cidr` o `--my-ip`)

**Scopo:** Controlla CHI può connettersi al server VPN (regola di ingresso del Security Group).

**Predefinito:** `0.0.0.0/0` (chiunque su internet - **meno sicuro**)

**Utilizzato per:**
- Regola in entrata del Security Group AWS per la porta VPN (UDP/51820)
- Controllo degli accessi e rafforzamento della sicurezza

**Quando personalizzare:**
- **Sempre!** Il predefinito `0.0.0.0/0` consente a chiunque di tentare connessioni VPN
- Usa `--my-ip` per limitare al tuo IP pubblico corrente (più sicuro)
- Usa `--allowed-cidr` per specificare un intervallo IP noto (rete ufficio, ISP casa)

**Valori validi:**
- Qualsiasi notazione CIDR valida (IPv4 o IPv6)
- Può essere specificato più volte per più intervalli consentiti
- Usa `/32` per singoli indirizzi IP (es. `203.0.113.42/32`)

**Esempi:**
```bash
# Rileva automaticamente il tuo IP pubblico (consigliato)
./another_betterthannothing_vpn.sh create --my-ip

# Specifica manualmente il tuo IP
./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.42/32

# Consenti le reti di casa e ufficio
./another_betterthannothing_vpn.sh create \
  --allowed-cidr 203.0.113.0/24 \
  --allowed-cidr 198.51.100.0/24

# Consenti a chiunque (non consigliato - visualizza avviso di sicurezza)
./another_betterthannothing_vpn.sh create --allowed-cidr 0.0.0.0/0
```

### Confronto Visivo

```
┌─────────────────────────────────────────────────────────────┐
│  VPC CIDR (--vpc-cidr)                                      │
│  "Qual è l'intervallo di rete interno?"                     │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  VPC: 10.10.0.0/16                                    │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  Subnet: 10.10.1.0/24                           │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  Istanza EC2: 10.10.1.42                  │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  CIDR Ingresso Consentito (--allowed-cidr / --my-ip)        │
│  "Chi può connettersi alla VPN?"                            │
│                                                             │
│  Internet                                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Tuo IP: 203.0.113.42/32  ✅ CONSENTITO             │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Altro IP: 198.51.100.99   ❌ BLOCCATO              │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Regola Security Group:                                     │
│  Consenti UDP/51820 da 203.0.113.42/32                      │
└─────────────────────────────────────────────────────────────┘
```

### Errori Comuni

❌ **Usare un intervallo IP pubblico per VPC CIDR:**
```bash
# SBAGLIATO - 8.8.8.0/24 è un intervallo IP pubblico
./another_betterthannothing_vpn.sh create --vpc-cidr 8.8.8.0/24
# Errore: VPC CIDR deve essere un intervallo di indirizzi privati (RFC 1918)
```

❌ **Confondere i due parametri:**
```bash
# SBAGLIATO - Usare VPC CIDR per il controllo degli accessi
./another_betterthannothing_vpn.sh create --allowed-cidr 10.10.0.0/16
# Questo consente a chiunque in 10.10.0.0/16 di connettersi, ma quello è l'intervallo interno del tuo VPC!
```

✅ **Utilizzo corretto:**
```bash
# GIUSTO - Separare le preoccupazioni
./another_betterthannothing_vpn.sh create \
  --my-ip \                    # Controllo accessi: solo il mio IP
  --vpc-cidr 172.16.0.0/16     # Rete interna: intervallo personalizzato
```

## Router Peers (VPN Site-to-Site)

### Panoramica

I router peer permettono di connettere intere reti LAN alla tua VPN, non solo singoli dispositivi. Questo è utile per:
- Connettere una rete domestica/ufficio alla VPC AWS
- VPN site-to-site tra diverse sedi
- Instradare traffico da dispositivi IoT o server dietro un router

### Come Funziona

Quando crei un router peer:
1. L'IP VPN del peer E tutte le subnet LAN specificate vengono aggiunte agli AllowedIPs del server
2. Il traffico dai dispositivi LAN viene instradato attraverso il tunnel VPN
3. Non viene usato SNAT - routing L3 puro (i dispositivi mantengono i loro IP originali)
4. MSS clamping opzionale previene problemi di frammentazione TCP

### Creare un Router Peer

```bash
# Crea VPN con router peer per LAN 192.168.0.0/24
./another_betterthannothing_vpn.sh create --my-ip \
    --peer-type router \
    --router-subnet 192.168.0.0/24 \
    --mss-clamping

# Subnet LAN multiple
./another_betterthannothing_vpn.sh create --my-ip \
    --peer-type router \
    --router-subnet 192.168.0.0/24 \
    --router-subnet 192.168.1.0/24 \
    --router-subnet 10.0.0.0/24 \
    --mss-clamping
```

### Esempio Configurazione Router

Sul tuo router (es. OpenWrt, pfSense, router Linux), la configurazione generata apparirà così:

```ini
[Interface]
PrivateKey = <chiave-privata-router>
Address = 10.99.0.2/32
DNS = 1.1.1.1
MTU = 1360
PostUp = iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280
PostDown = iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280

[Peer]
PublicKey = <chiave-pubblica-server>
PresharedKey = <chiave-preshared>
Endpoint = <ip-server>:51820
AllowedIPs = 10.10.0.0/16
PersistentKeepalive = 25
```

### Configurazione Lato Server

Il `wg0.conf` del server includerà le subnet del router negli AllowedIPs:

```ini
[Peer]
PublicKey = <chiave-pubblica-router>
PresharedKey = <chiave-preshared>
AllowedIPs = 10.99.0.2/32, 192.168.0.0/24, 192.168.1.0/24
```

### Requisiti Setup Router

Sul tuo router, devi:

1. **Abilitare IP forwarding** (solitamente già abilitato sui router)
2. **Aggiungere route** per il CIDR VPC che puntano all'interfaccia WireGuard
3. **Configurare firewall** per permettere il forwarding tra LAN e WireGuard

Esempio per router Linux:
```bash
# Abilita IP forwarding (se non già abilitato)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Aggiungi route verso VPC via WireGuard
ip route add 10.10.0.0/16 dev wg0

# Permetti forwarding (iptables)
iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

## Supporto Elastic IP (EIP)

### Cos'è un Elastic IP?

Un Elastic IP (EIP) è un indirizzo IPv4 pubblico statico che persiste anche quando fermi e avvii la tua istanza EC2. Senza un EIP, il tuo server VPN ottiene un nuovo indirizzo IP pubblico ogni volta che l'istanza viene fermata e riavviata, richiedendoti di rigenerare tutte le configurazioni client.

### Quando Usare EIP

**Usa EIP quando:**
- ✅ Pianifichi di fermare/avviare l'istanza frequentemente per risparmiare sui costi
- ✅ Hai bisogno di un endpoint VPN persistente che non cambia
- ✅ Vuoi evitare di rigenerare le configurazioni client dopo i riavvii dell'istanza
- ✅ Stai usando la VPN per progetti a lungo termine (settimane/mesi)

**Salta EIP quando:**
- ❌ Stai creando una VPN veramente effimera (crea → usa → elimina in una sessione)
- ❌ Vuoi minimizzare i costi (EIP costa ~$3.60/mese quando l'istanza è fermata)
- ❌ Non ti dispiace rigenerare le configurazioni client se l'IP cambia

### Considerazioni sui Costi

**Prezzi EIP (a partire dal 2026):**
- **Mentre l'istanza è in esecuzione:** Gratuito (nessun costo aggiuntivo)
- **Mentre l'istanza è fermata:** ~$0.005/ora = ~$3.60/mese
- **Se non associato a un'istanza:** ~$0.005/ora = ~$3.60/mese

**Scenari di costo di esempio:**

| Scenario | Senza EIP | Con EIP |
|----------|-----------|---------|
| Sempre in esecuzione (730h/mese) | $3.02/mese | $3.02/mese (nessun costo extra) |
| Esegui 8h/giorno, ferma 16h/giorno | $1.01/mese | $2.81/mese ($1.80 costo EIP) |
| Esegui 1 giorno/settimana, fermato il resto | $0.43/mese | $3.17/mese ($2.74 costo EIP) |

**Intuizione chiave:** EIP è conveniente se la tua istanza è in esecuzione la maggior parte del tempo. Se fermi l'istanza frequentemente, EIP aggiunge un costo significativo.

### Come Usare EIP

Per allocare un Elastic IP per il tuo server VPN, usa il flag `--eip` quando crei lo stack:

```bash
# Crea VPN con Elastic IP
./another_betterthannothing_vpn.sh create --my-ip --eip

# Con altre opzioni
./another_betterthannothing_vpn.sh create --my-ip --eip --mode full --region eu-west-1
```

L'Elastic IP verrà automaticamente allocato e associato alla tua istanza VPN. L'indirizzo IP persisterà anche se fermi e avvii l'istanza.

### Cosa Succede Senza EIP

Quando fermi e avvii un'istanza EC2 senza un EIP:

1. **L'istanza si ferma:** La VPN diventa non disponibile
2. **L'istanza si avvia:** AWS assegna un nuovo IP pubblico casuale
3. **Le configurazioni client si rompono:** Tutte le configurazioni client esistenti puntano al vecchio IP
4. **Correzione manuale richiesta:** Devi:
   - Ottenere il nuovo IP: `./another_betterthannothing_vpn.sh status --name <nome-stack>`
   - Rigenerare tutte le configurazioni client: `./another_betterthannothing_vpn.sh add-client --name <nome-stack>`
   - Ridistribuire le nuove configurazioni a tutti i dispositivi

### Best Practice

1. **Per VPN effimere (ore/giorni):** Salta EIP, elimina lo stack quando hai finito
2. **Per VPN persistenti (settimane/mesi):** Usa EIP per evitare cambiamenti di IP
3. **Per l'ottimizzazione dei costi:** Se usi EIP, mantieni l'istanza in esecuzione o elimina completamente lo stack (non lasciarla fermata)
4. **Per i test:** Inizia senza EIP, aggiungilo in seguito se necessario (richiede ricreazione dello stack)


## Best Practice di Sicurezza

### 1. Limita Sempre il CIDR di Ingresso

**❌ Non usare mai il predefinito `0.0.0.0/0` in produzione:**
```bash
# MALE - Chiunque può tentare di connettersi
./another_betterthannothing_vpn.sh create
```

**✅ Usa sempre `--my-ip` o `--allowed-cidr` specifico:**
```bash
# BENE - Solo il tuo IP può connettersi
./another_betterthannothing_vpn.sh create --my-ip

# BENE - Solo la rete del tuo ufficio può connettersi
./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.0/24
```

**Perché è importante:** Sebbene WireGuard richieda autenticazione crittografica, limitare il CIDR di ingresso riduce la superficie di attacco e previene scansioni di porte, tentativi DoS e attacchi brute-force.

### 2. Usa Istanze Spot per Carichi di Lavoro Temporanei

Se stai usando la VPN per attività a breve termine, usa `--spot` per risparmiare ~70% sui costi di calcolo:

```bash
./another_betterthannothing_vpn.sh create --my-ip --spot
```

**Compromesso:** Le istanze Spot possono essere interrotte con 2 minuti di preavviso. Non adatte per connessioni di lunga durata.

### 3. Ruota Regolarmente l'Infrastruttura VPN

Per casi d'uso temporanei, distruggi e ricrea periodicamente la VPN:

```bash
# Elimina il vecchio stack
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes

# Crea un nuovo stack con chiavi fresche
./another_betterthannothing_vpn.sh create --my-ip
```

**Vantaggi:**
- Chiavi crittografiche fresche
- Nuovo indirizzo IP
- Istanza pulita (nessun log o stato accumulato)
- Costi ridotti (paghi solo per ciò che usi)

### 4. Proteggi i File di Configurazione Client

I file di configurazione client contengono chiavi private. Proteggili:

```bash
# Verifica i permessi (dovrebbero essere 600)
ls -la ./another_betterthannothing_vpn_config/*/clients/*.conf

# Se necessario, correggi i permessi
chmod 600 ./another_betterthannothing_vpn_config/*/clients/*.conf

# Elimina le configurazioni quando non sono più necessarie
rm -rf ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/
```

### 5. Funzionalità di Sicurezza WireGuard

Questa VPN implementa diverse best practice di sicurezza WireGuard:

**PresharedKey (Resistenza Post-Quantum):**
Ogni connessione client utilizza una PresharedKey unica oltre alla coppia standard di chiavi pubblica/privata. Questo fornisce un ulteriore livello di crittografia simmetrica che offre protezione contro potenziali futuri attacchi di computer quantistici.

**Ottimizzazione MTU:**
L'MTU è impostato a 1360 byte per prevenire problemi di frammentazione comuni con tunnel VPN su connessioni EC2/NAT, garantendo connessioni stabili e affidabili.

**Archiviazione Chiavi:**
- Le configurazioni client (file `.conf`) sono salvate con permessi 600
- Le chiavi pubbliche sono salvate separatamente nella directory `keys/` per riferimento
- Le chiavi private non lasciano mai il file di configurazione client

```bash
# Struttura directory di output
./another_betterthannothing_vpn_config/abthn-vpn-XXXXXXXX-XXXX/
├── clients/
│   ├── client-1.conf    # Config WireGuard completa (chiave privata inclusa)
│   └── client-2.conf
├── keys/
│   ├── server.pub       # Chiave pubblica del server
│   ├── client-1.pub     # Chiave pubblica client 1
│   └── client-2.pub     # Chiave pubblica client 2
└── metadata.json        # Metadati dello stack
```

### 6. Usa la Modalità Split-Tunnel Quando Possibile

La modalità split-tunnel (`--mode split`) instrada solo il traffico VPC attraverso la VPN, lasciando il traffico internet sulla tua connessione locale:

**Vantaggi:**
- Migliori prestazioni (il traffico internet non passa attraverso la VPN)
- Costi di trasferimento dati inferiori (solo il traffico VPC usa la larghezza di banda AWS)
- Latenza ridotta per la navigazione generale
- Carico ridotto sul server VPN

**Usa full-tunnel solo quando:**
- Devi nascondere il tuo indirizzo IP pubblico
- Sei su una rete non affidabile (WiFi pubblico)
- Devi aggirare restrizioni basate su IP

### 7. Monitora i Costi con i Tag

Tutte le risorse sono taggate con `CostCenter=<nome-stack>`. Usa AWS Cost Explorer per tracciare la spesa:

1. Vai a AWS Cost Explorer
2. Filtra per tag: `CostCenter = abthn-vpn-20260201-a3f9`
3. Visualizza i costi per servizio (EC2, trasferimento dati, ecc.)

### 8. Abilita VPC Flow Logs (Opzionale)

Per tracce di audit, abilita VPC Flow Logs:

```bash
# Dopo aver creato lo stack, abilita i flow logs tramite AWS Console o CLI
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/another-betterthannothing-vpn
```

**Nota:** I Flow Logs comportano costi aggiuntivi (~$0.50 per GB ingerito).

### 9. IMDSv2 è Applicato

Il template CloudFormation applica IMDSv2 (Instance Metadata Service versione 2) per prevenire attacchi SSRF:

- `HttpTokens: required` - Richiede token di sessione
- `HttpPutResponseHopLimit: 1` - Previene l'inoltro da container

Questo è configurato automaticamente; nessuna azione necessaria.

### 9. Nessun Accesso SSH

Il Security Group NON consente SSH (porta 22). Tutto l'accesso avviene tramite SSM:

```bash
# Usa SSM per l'accesso interattivo
./another_betterthannothing_vpn.sh ssm --name <nome-stack>
```

**Vantaggi:**
- Nessuna gestione di chiavi SSH
- Nessuna porta SSH esposta
- Autenticazione basata su IAM
- Registrazione delle sessioni tramite CloudTrail

### 10. Rivedi il Template CloudFormation

Prima di rilasciare, rivedi il `template.yaml` per capire quali risorse vengono create:

```bash
# Visualizza il template
cat template.yaml

# Valida il template
aws cloudformation validate-template --template-body file://template.yaml
```


## Considerazioni sui Costi

### Stime dei Prezzi (us-east-1, a partire dal 2026)

**Istanza On-Demand (t4g.nano):**
- Calcolo: ~$0.0042/ora = ~$3.02/mese (se in esecuzione 24/7)
- Trasferimento dati OUT: $0.09/GB (primi 100 GB/mese gratuiti)
- Trasferimento dati IN: Gratuito

**Istanza Spot (t4g.nano):**
- Calcolo: ~$0.0013/ora = ~$0.94/mese (se in esecuzione 24/7)
- Risparmio: ~70% rispetto a on-demand
- Rischio: Può essere interrotta con 2 minuti di preavviso

**Altri Costi:**
- CloudFormation: Gratuito
- VPC: Gratuito (nessun NAT Gateway o VPC endpoint)
- Security Groups: Gratuito
- SSM: Gratuito (nessun costo aggiuntivo per Session Manager)
- EBS: ~$0.08/GB-mese (volume root da 8 GB = ~$0.64/mese)

**Costo Mensile Totale (operazione 24/7):**
- On-demand: ~$3.66/mese
- Spot: ~$1.58/mese

**Pattern di Utilizzo Tipici:**

| Pattern di Utilizzo | Ore/Mese | Costo On-Demand | Costo Spot |
|---------------------|----------|-----------------|------------|
| Sempre attivo | 730 | $3.66 | $1.58 |
| Orario lavorativo (8h/giorno, 5 giorni/settimana) | 160 | $0.80 | $0.35 |
| Ad-hoc (10h/mese) | 10 | $0.05 | $0.02 |

**Costi di Trasferimento Dati:**

Assumendo 10 GB/mese di traffico VPN:
- Primi 100 GB: Gratuiti
- Aggiuntivi: $0.09/GB

**Suggerimenti per l'Ottimizzazione dei Costi:**

1. **Ferma quando non in uso:**
   ```bash
   ./another_betterthannothing_vpn.sh stop --name <nome-stack>
   ```
   Le istanze fermate comportano solo costi di storage EBS (~$0.64/mese).

2. **Usa istanze Spot:**
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --spot
   ```
   Risparmia ~70% sui costi di calcolo.

3. **Elimina quando hai finito:**
   ```bash
   ./another_betterthannothing_vpn.sh delete --name <nome-stack> --yes
   ```
   Costo zero quando lo stack è eliminato.

4. **Usa la modalità split-tunnel:**
   Solo il traffico VPC usa il trasferimento dati AWS. Il traffico internet rimane locale (gratuito).

5. **Scegli tipi di istanza più piccoli:**
   Per un utilizzo leggero, t4g.nano è sufficiente. Per carichi più pesanti, considera t4g.micro (~$6/mese).

### Tracciamento dei Costi con i Tag

Tutte le risorse sono taggate con `CostCenter=<nome-stack>`. Usa questo per tracciare i costi:

**AWS Cost Explorer:**
1. Naviga su AWS Cost Explorer
2. Clicca su "Cost & Usage Reports"
3. Aggiungi filtro: Tag → `CostCenter` → `<tuo-nome-stack>`
4. Visualizza la suddivisione per servizio

**AWS CLI:**
```bash
# Ottieni il costo per uno stack specifico (ultimi 30 giorni)
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-02-01 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter file://filter.json

# filter.json:
{
  "Tags": {
    "Key": "CostCenter",
    "Values": ["abthn-vpn-20260201-a3f9"]
  }
}
```

### Avvisi di Budget

Imposta un avviso di budget per evitare sorprese:

```bash
aws budgets create-budget \
  --account-id <tuo-account-id> \
  --budget file://budget.json

# budget.json:
{
  "BudgetName": "VPN-Monthly-Budget",
  "BudgetLimit": {
    "Amount": "10",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "TagKeyValue": ["user:CostCenter$abthn-vpn-*"]
  }
}
```


## Esempi

### Esempio 1: VPN Rapida per Accedere a un Database RDS Privato

Hai un database RDS in una subnet privata e devi connetterti dal tuo laptop:

```bash
# Crea VPN split-tunnel (solo traffico VPC)
./another_betterthannothing_vpn.sh create --my-ip --mode split --region us-east-1

# Importa la configurazione in WireGuard e connettiti
sudo wg-quick up client-1

# Connettiti a RDS (IP privato)
psql -h 10.10.1.123 -U admin -d mydb

# Quando hai finito, disconnettiti
sudo wg-quick down client-1

# Elimina lo stack
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

**Costo:** ~$0.05 per 1 ora di utilizzo.

### Esempio 2: Ambiente di Build Temporaneo

Hai bisogno di un ambiente Linux pulito per compilare un progetto:

```bash
# Crea VPN con istanza Spot
./another_betterthannothing_vpn.sh create --my-ip --spot

# Apri sessione SSM
./another_betterthannothing_vpn.sh ssm --name abthn-vpn-20260201-a3f9

# All'interno dell'istanza
sudo dnf install -y gcc make git docker
git clone https://github.com/myproject/repo.git
cd repo
make build

# Copia gli artefatti su S3
aws s3 cp ./build/output s3://my-bucket/artifacts/

# Esci ed elimina
exit
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

### Esempio 3: Accesso VPN Multi-Dispositivo

Hai bisogno di accesso VPN da laptop, telefono e tablet:

```bash
# Crea VPN con 3 client iniziali
./another_betterthannothing_vpn.sh create --my-ip --clients 3

# Le configurazioni sono generate:
# ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-1.conf (laptop)
# ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-2.conf (telefono)
# ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-3.conf (tablet)

# Trasferisci le configurazioni ai dispositivi (AirDrop, email, ecc.)
# Importa ogni configurazione nell'app WireGuard del rispettivo dispositivo

# Successivamente, aggiungi un 4° dispositivo
./another_betterthannothing_vpn.sh add-client --name abthn-vpn-20260201-a3f9
```

### Esempio 4: VPN Full-Tunnel per WiFi Pubblico

Sei in un bar e vuoi crittografare tutto il traffico:

```bash
# Crea VPN full-tunnel
./another_betterthannothing_vpn.sh create --my-ip --mode full

# Importa la configurazione e connettiti
sudo wg-quick up client-1

# Tutto il traffico ora passa attraverso AWS
curl ifconfig.me
# Mostra l'IP pubblico dell'istanza EC2 AWS

# Quando hai finito
sudo wg-quick down client-1
```

### Esempio 5: Distribuzione Multi-Regione

Hai bisogno di accesso VPN in più regioni:

```bash
# Crea VPN in us-east-1
./another_betterthannothing_vpn.sh create --my-ip --region us-east-1 --name vpn-us-east

# Crea VPN in eu-west-1
./another_betterthannothing_vpn.sh create --my-ip --region eu-west-1 --name vpn-eu-west

# Crea VPN in ap-southeast-1
./another_betterthannothing_vpn.sh create --my-ip --region ap-southeast-1 --name vpn-ap-se

# Elenca tutte le VPN
./another_betterthannothing_vpn.sh list --region us-east-1
./another_betterthannothing_vpn.sh list --region eu-west-1
./another_betterthannothing_vpn.sh list --region ap-southeast-1

# Connettiti alla regione più vicina per la migliore latenza
```

### Esempio 6: CIDR VPC Personalizzato per Evitare Conflitti

La tua VPN aziendale usa `10.0.0.0/8`, quindi hai bisogno di un intervallo diverso:

```bash
# Usa l'intervallo 172.16.x.x invece
./another_betterthannothing_vpn.sh create \
  --my-ip \
  --vpc-cidr 172.16.0.0/16 \
  --mode split

# La configurazione client avrà AllowedIPs = 172.16.0.0/16
# Nessun conflitto con la VPN aziendale (10.0.0.0/8)
```

### Esempio 7: Consentire Più IP Sorgente

Vuoi consentire connessioni sia da casa che dall'ufficio:

```bash
./another_betterthannothing_vpn.sh create \
  --allowed-cidr 203.0.113.0/24 \
  --allowed-cidr 198.51.100.0/24 \
  --mode split
```

### Esempio 8: Esecuzione di Carichi di Lavoro Docker

Usa il server VPN come host Docker temporaneo:

```bash
# Crea VPN
./another_betterthannothing_vpn.sh create --my-ip

# Apri sessione SSM
./another_betterthannothing_vpn.sh ssm --name abthn-vpn-20260201-a3f9

# Installa Docker
sudo dnf install -y docker
sudo systemctl start docker

# Esegui un database PostgreSQL
sudo docker run -d \
  --name postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=testpass \
  postgres:15

# Dal tuo laptop (connesso tramite VPN)
psql -h 10.10.1.x -U postgres
# Inserisci password: testpass

# Quando hai finito, elimina tutto
exit
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

## Log di Esecuzione

Lo script salva automaticamente i log di esecuzione per tracciare le informazioni degli stack tra diverse esecuzioni. Questo è utile per:
- Recuperare informazioni sugli stack dopo la fine di una sessione
- Tracciare lo stato degli stack creati
- Trovare la directory di output corretta quando si eliminano gli stack

### Posizione dei Log

I log di esecuzione vengono salvati nella directory di output (predefinita: `./another_betterthannothing_vpn_config/`) come `execution_log.json`.

### Contenuto dei Log

Il file di log contiene un array di voci, una per stack:

```json
[
  {
    "stack_name": "abthn-vpn-20260204-x1y2",
    "region": "eu-west-1",
    "status": "READY",
    "last_updated": "2026-02-04T10:30:00Z",
    "output_dir": "/home/user/vpn",
    "additional_info": "VPN setup complete, 2 client(s) configured"
  }
]
```

### Valori di Stato

- `CREATING` - Creazione dello stack avviata
- `CREATE_COMPLETE` - Stack CloudFormation creato con successo
- `CREATE_FAILED` - Creazione dello stack fallita
- `READY` - VPN completamente configurata e pronta all'uso
- `DELETED` - Stack eliminato

### Usare i Log per il Recupero

Se hai bisogno di trovare informazioni su uno stack creato in precedenza:

```bash
# Visualizza tutti gli stack registrati
cat ./another_betterthannothing_vpn_config/execution_log.json | jq '.'

# Trova uno stack specifico
cat ./another_betterthannothing_vpn_config/execution_log.json | jq '.[] | select(.stack_name == "abthn-vpn-20260204-x1y2")'

# Elenca tutti gli stack con il loro stato
cat ./another_betterthannothing_vpn_config/execution_log.json | jq '.[] | {name: .stack_name, status: .status, region: .region}'
```

## Risoluzione dei Problemi

### Problemi con l'Agente SSM

**Problema:** Lo script va in timeout aspettando che l'agente SSM sia pronto.

**Sintomi:**
```
Waiting for SSM agent to be ready...
Timeout: SSM agent did not become ready after 5 minutes
```

**Soluzioni:**

1. **Controlla i log di sistema dell'istanza:**
   ```bash
   aws ec2 get-console-output --instance-id <instance-id>
   ```
   Cerca errori durante l'avvio o l'avvio dell'agente SSM.

2. **Verifica l'allegato del ruolo IAM:**
   ```bash
   aws ec2 describe-instances --instance-ids <instance-id> \
     --query 'Reservations[0].Instances[0].IamInstanceProfile'
   ```
   Dovrebbe mostrare l'ARN del profilo dell'istanza.

3. **Controlla manualmente lo stato dell'agente SSM:**
   ```bash
   # Aspetta qualche minuto in più, poi prova
   aws ssm describe-instance-information \
     --filters "Key=InstanceIds,Values=<instance-id>"
   ```

4. **Verifica la connettività internet:**
   - L'istanza ha bisogno di accesso a internet per raggiungere gli endpoint SSM
   - Controlla che la route table abbia una route predefinita verso l'Internet Gateway
   - Controlla che il Security Group consenta HTTPS in uscita (443)

5. **Riavvia l'agente SSM (se puoi accedere tramite EC2 Serial Console):**
   ```bash
   sudo systemctl restart amazon-ssm-agent
   ```

**Prevenzione:**
- Usa il CIDR VPC predefinito e le impostazioni del Security Group
- Assicurati che il template CloudFormation non sia stato modificato
- Controlla il dashboard di stato dei servizi AWS per interruzioni SSM

### Problemi di Connessione WireGuard

**Problema:** La connessione VPN fallisce o va in timeout.

**Sintomi:**
- WireGuard mostra "Handshake failed" o "No recent handshake"
- Nessun traffico fluisce attraverso il tunnel

**Soluzioni:**

1. **Verifica che l'endpoint sia corretto:**
   ```bash
   # Controlla l'IP pubblico corrente
   ./another_betterthannothing_vpn.sh status --name <nome-stack>
   
   # Confronta con la configurazione client
   grep Endpoint ./another_betterthannothing_vpn_config/<nome-stack>/clients/client-1.conf
   ```
   
   Se gli IP non corrispondono (l'istanza è stata fermata/avviata), rigenera la configurazione client:
   ```bash
   ./another_betterthannothing_vpn.sh add-client --name <nome-stack>
   ```

2. **Controlla che il Security Group consenta il tuo IP:**
   ```bash
   aws ec2 describe-security-groups \
     --filters "Name=tag:CostCenter,Values=<nome-stack>" \
     --query 'SecurityGroups[0].IpPermissions'
   ```
   
   Se il tuo IP è cambiato, ricrea lo stack con `--my-ip` o aggiorna manualmente il Security Group.

3. **Verifica che il servizio WireGuard sia in esecuzione:**
   ```bash
   ./another_betterthannothing_vpn.sh ssm --name <nome-stack>
   sudo systemctl status wg-quick@wg0
   sudo wg show
   ```

4. **Controlla conflitti di porte:**
   ```bash
   # Sulla tua macchina locale
   sudo wg show
   # Assicurati che nessun'altra interfaccia WireGuard stia usando le stesse chiavi
   ```

5. **Testa la connettività alla porta VPN:**
   ```bash
   # Dalla tua macchina
   nc -zvu <server-public-ip> 51820
   ```
   
   Se questo fallisce, controlla:
   - Il tuo firewall consente UDP/51820 in uscita
   - Il tuo ISP non blocca i protocolli VPN
   - Il Security Group consente il tuo IP corrente

6. **Rigenera le chiavi:**
   ```bash
   # Elimina e ricrea lo stack
   ./another_betterthannothing_vpn.sh delete --name <nome-stack> --yes
   ./another_betterthannothing_vpn.sh create --my-ip
   ```

### Fallimenti dello Stack CloudFormation

**Problema:** La creazione dello stack fallisce.

**Sintomi:**
```
Stack creation failed: CREATE_FAILED
Resource: VpnInstance
Reason: You have exceeded your maximum instance limit
```

**Soluzioni:**

1. **Controlla gli eventi dello stack:**
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name <nome-stack> \
     --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
   ```

2. **Fallimenti comuni e correzioni:**

   **Capacità EC2 insufficiente:**
   ```
   Reason: We currently do not have sufficient t4g.nano capacity
   ```
   Soluzione: Usa un tipo di istanza o regione diversi:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --instance-type t4g.micro
   # oppure
   ./another_betterthannothing_vpn.sh create --my-ip --region us-west-2
   ```

   **Limite di istanze superato:**
   ```
   Reason: You have exceeded your maximum instance limit
   ```
   Soluzione: Richiedi un aumento del limite tramite AWS Service Quotas o elimina istanze inutilizzate.

   **CIDR non valido:**
   ```
   Reason: The CIDR '8.8.8.0/24' is invalid
   ```
   Soluzione: Usa un CIDR privato RFC 1918 valido:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 10.10.0.0/16
   ```

3. **Pulisci lo stack fallito:**
   ```bash
   aws cloudformation delete-stack --stack-name <nome-stack>
   aws cloudformation wait stack-delete-complete --stack-name <nome-stack>
   ```


### Fallimenti nel Rilevamento dell'IP

**Problema:** Il flag `--my-ip` non riesce a rilevare l'IP pubblico.

**Sintomi:**
```
Error: Unable to detect public IP. Please use --allowed-cidr <your-ip>/32 instead.
```

**Soluzioni:**

1. **Controlla la connettività internet:**
   ```bash
   curl -s https://api.ipify.org
   # Dovrebbe restituire il tuo IP pubblico
   ```

2. **Usa la specifica manuale dell'IP:**
   ```bash
   # Trova il tuo IP manualmente
   curl ifconfig.me
   
   # Usalo nel comando
   ./another_betterthannothing_vpn.sh create --allowed-cidr $(curl -s ifconfig.me)/32
   ```

3. **Controlla se sei dietro un proxy aziendale:**
   Se sei dietro un proxy aziendale, l'IP rilevato potrebbe essere quello del proxy. Verifica con il tuo amministratore di rete.

### Problemi di Importazione della Configurazione Client

**Problema:** Il client WireGuard rifiuta il file di configurazione.

**Sintomi:**
- "Invalid configuration file"
- "Unable to parse configuration"

**Soluzioni:**

1. **Verifica l'integrità del file:**
   ```bash
   cat ./another_betterthannothing_vpn_config/<nome-stack>/clients/client-1.conf
   ```
   
   Dovrebbe contenere sezioni `[Interface]` e `[Peer]` con tutti i campi richiesti.

2. **Controlla i permessi del file:**
   ```bash
   ls -la ./another_betterthannothing_vpn_config/<nome-stack>/clients/client-1.conf
   # Dovrebbe essere -rw------- (600)
   
   chmod 600 ./another_betterthannothing_vpn_config/<nome-stack>/clients/client-1.conf
   ```

3. **Rigenera la configurazione:**
   ```bash
   ./another_betterthannothing_vpn.sh add-client --name <nome-stack>
   ```

### Problemi di Prestazioni

**Problema:** Velocità VPN lente o alta latenza.

**Soluzioni:**

1. **Usa la modalità split-tunnel:**
   Instrada solo il traffico VPC attraverso la VPN:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --mode split
   ```

2. **Scegli una regione più vicina:**
   Distribuisci la VPN in una regione geograficamente più vicina a te:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --region eu-west-1
   ```

3. **Aggiorna il tipo di istanza:**
   ```bash
   # Ferma l'istanza corrente
   ./another_betterthannothing_vpn.sh stop --name <nome-stack>
   
   # Modifica il tipo di istanza tramite AWS Console o CLI
   aws ec2 modify-instance-attribute \
     --instance-id <instance-id> \
     --instance-type t4g.small
   
   # Avvia l'istanza
   ./another_betterthannothing_vpn.sh start --name <nome-stack>
   ```

4. **Controlla la congestione della rete:**
   ```bash
   # Testa la latenza
   ping <server-public-ip>
   
   # Testa la larghezza di banda
   iperf3 -c <server-private-ip>  # Richiede iperf3 sul server
   ```

### Interruzioni delle Istanze Spot

**Problema:** L'istanza Spot è stata terminata inaspettatamente.

**Sintomi:**
- La connessione VPN si interrompe
- Lo stato dell'istanza mostra "terminated"

**Soluzioni:**

1. **Controlla l'avviso di interruzione:**
   ```bash
   aws ec2 describe-spot-instance-requests \
     --filters "Name=instance-id,Values=<instance-id>"
   ```

2. **Ricrea con on-demand:**
   ```bash
   ./another_betterthannothing_vpn.sh delete --name <nome-stack> --yes
   ./another_betterthannothing_vpn.sh create --my-ip  # Senza --spot
   ```

3. **Usa Spot solo per carichi di lavoro non critici:**
   Le istanze Spot sono ideali per carichi di lavoro temporanei e interrompibili.

### Ottenere Aiuto

Se sei ancora bloccato:

1. **Controlla i log di AWS CloudTrail** per errori API
2. **Rivedi gli eventi dello stack CloudFormation** per messaggi di errore dettagliati


## Pulizia

### Eliminare uno Stack VPN

Per rimuovere tutte le risorse AWS e smettere di incorrere in costi:

```bash
# Interattivo (richiede conferma)
./another_betterthannothing_vpn.sh delete --name <nome-stack>

# Non interattivo (salta la conferma)
./another_betterthannothing_vpn.sh delete --name <nome-stack> --yes
```

**Cosa viene eliminato:**
- ✅ Stack CloudFormation
- ✅ Istanza EC2
- ✅ VPC e tutte le risorse di rete (subnet, route table, Internet Gateway)
- ✅ Security Group
- ✅ Ruolo IAM e Instance Profile
- ✅ Volumi EBS

**Cosa NON viene eliminato:**
- ❌ File di configurazione client locali in `./another_betterthannothing_vpn_config/`
- ❌ Log CloudWatch (se hai abilitato VPC Flow Logs)
- ❌ Qualsiasi dato che hai memorizzato sull'istanza

### Eliminare i File di Configurazione Locali

I file di configurazione client sono memorizzati localmente e contengono chiavi private. Eliminali quando non sono più necessari:

```bash
# Elimina le configurazioni per uno stack specifico
rm -rf ./another_betterthannothing_vpn_config/<nome-stack>/

# Elimina tutte le configurazioni VPN
rm -rf ./another_betterthannothing_vpn_config/
```

### Verificare l'Eliminazione

Conferma che tutte le risorse siano state eliminate:

```bash
# Controlla lo stato dello stack
aws cloudformation describe-stacks --stack-name <nome-stack>
# Dovrebbe restituire: "Stack with id <nome-stack> does not exist"

# Elenca tutti gli stack VPN
./another_betterthannothing_vpn.sh list --region <regione>
# Non dovrebbe mostrare lo stack eliminato

# Controlla risorse orfane (raro, ma possibile)
aws ec2 describe-instances \
  --filters "Name=tag:CostCenter,Values=<nome-stack>" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'
# Dovrebbe restituire vuoto
```

### Pulizia di Più Stack

Se hai più stack VPN in diverse regioni:

```bash
# Elenca tutti gli stack in tutte le regioni
for region in us-east-1 us-west-2 eu-west-1; do
  echo "Region: $region"
  ./another_betterthannothing_vpn.sh list --region $region
done

# Elimina tutti gli stack (fai attenzione!)
for region in us-east-1 us-west-2 eu-west-1; do
  for stack in $(aws cloudformation list-stacks \
    --region $region \
    --query 'StackSummaries[?starts_with(StackName, `abthn-vpn-`) && StackStatus!=`DELETE_COMPLETE`].StackName' \
    --output text); do
    echo "Deleting $stack in $region"
    ./another_betterthannothing_vpn.sh delete --name $stack --region $region --yes
  done
done
```

### Costo Dopo l'Eliminazione

Una volta eliminato lo stack, dovresti vedere:
- **Costi EC2:** Si fermano immediatamente
- **Costi EBS:** Si fermano immediatamente
- **Costi di trasferimento dati:** Solo per i dati trasferiti prima dell'eliminazione
- **CloudFormation:** Nessun costo (sempre gratuito)

**Verifica costo zero:**
1. Aspetta 24-48 ore per l'aggiornamento della fatturazione
2. Controlla AWS Cost Explorer filtrato per `CostCenter=<nome-stack>`
3. Non dovrebbero esserci nuovi costi dopo il timestamp di eliminazione

### Risoluzione dei Problemi di Eliminazione

**Problema:** L'eliminazione dello stack fallisce o si blocca.

**Sintomi:**
```
Stack deletion failed: DELETE_FAILED
Resource: VpnInstance
Reason: resource sg-xxxxx has a dependent object
```

**Soluzioni:**

1. **Controlla gli eventi dello stack:**
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name <nome-stack> \
     --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]'
   ```

2. **Fallimenti di eliminazione comuni:**

   **ENI ancora allegato:**
   ```bash
   # Trova ed elimina l'ENI manualmente
   aws ec2 describe-network-interfaces \
     --filters "Name=tag:CostCenter,Values=<nome-stack>"
   
   aws ec2 delete-network-interface --network-interface-id <eni-id>
   ```

   **Security Group ha dipendenze:**
   ```bash
   # Trova risorse dipendenti
   aws ec2 describe-security-groups \
     --group-ids <sg-id> \
     --query 'SecurityGroups[0].IpPermissions'
   
   # Elimina prima le risorse dipendenti, poi riprova l'eliminazione dello stack
   ```

3. **Eliminazione forzata (ultima risorsa):**
   ```bash
   # Elimina manualmente le risorse tramite AWS Console
   # Poi elimina lo stack
   aws cloudformation delete-stack --stack-name <nome-stack>
   ```

### Best Practice per la Pulizia

1. **Elimina gli stack quando non in uso:** Non lasciare l'infrastruttura VPN in esecuzione inattiva
2. **Imposta promemoria nel calendario:** Se crei una VPN per un'attività specifica, imposta un promemoria per eliminarla
3. **Usa AWS Budgets:** Imposta avvisi per notificarti di costi imprevisti
4. **Audit regolari:** Esegui periodicamente il comando `list` per controllare stack dimenticati
5. **Tagga tutto:** Il tag `CostCenter` rende facile tracciare e pulire le risorse

---

## Licenza

Questo progetto è fornito così com’è per uso educativo e personale, sotto licenza Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0), e viene utilizzato a proprio rischio.

Vedi il file [LICENSE](LICENSE) per i dettagli.

## Contribuire

I contributi sono benvenuti! Apri un issue o una pull request sul repository del progetto.

## Ringraziamenti

- **WireGuard:** Protocollo VPN moderno, veloce e sicuro
- **AWS Systems Manager:** Accesso sicuro alle istanze senza SSH
- **AWS CloudFormation:** Infrastructure as Code per distribuzioni riproducibili

---

**Ricorda:** Questa è una VPN "meglio di niente" per casi d'uso temporanei. Per carichi di lavoro di produzione o dati sensibili, usa soluzioni VPN aziendali con adeguata ridondanza, monitoraggio e certificazioni di conformità.
