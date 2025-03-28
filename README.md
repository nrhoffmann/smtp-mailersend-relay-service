# SMTP to MailerSend Relay

A Node.js SMTP server that receives emails locally and forwards them via the MailerSend API.

## Why

DigitalOcean doesn't allow outbound SMTP request. This service uses http to forward SMTP emails through MailSend.

## Features

- **Local SMTP Server**: Listens on localhost:2525 for incoming emails
- **Email Parsing**: Deconstructs emails into their components
- **MailerSend Integration**: Forwards emails through MailerSend API
- **Attachment Support**: Handles email attachments correctly
- **Systemd Service**: Runs as a system service on Ubuntu

## Security Features

- **Localhost Only**: SMTP server only binds to 127.0.0.1
- **No Authentication**: Simple setup for local-only access
- **Service Isolation**: Systemd security protections

## Installation

### Prerequisites

- Ubuntu server
- Git
- Node.js (installed automatically if not present)

### Installation Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/smtp-mailersend-relay.git
   cd smtp-mailersend-relay
   ```

2. Run the installation script:
   ```bash
   sudo bash ./install.sh
   ```

3. Configure your MailerSend API key:
   ```bash
   sudo nano /opt/smtp-mailersend-relay/.env
   ```
   Update the `MAILERSEND_API_KEY` value.

4. Start the service:
   ```bash
   sudo systemctl start smtp-mailersend
   ```

## Updating the Service

When you update the code in the Git repository, you can update the running service:

1. On your server, run:
   ```bash
   sudo ./update.sh
   ```

## Usage

Once installed, the SMTP server will accept emails on port 2525 (or your configured port) on localhost.

Configure your applications to use `localhost:2525` as the SMTP server with no authentication required.

### Testing with swaks

You can test the service with the `swaks` tool:

```bash
swaks --to recipient@example.com --from sender@example.com --server localhost --port 2525 --body "Test email body"
```

## Monitoring

Check service status:
```bash
sudo systemctl status smtp-mailersend
```

View logs:
```bash
sudo journalctl -u smtp-mailersend -f
```