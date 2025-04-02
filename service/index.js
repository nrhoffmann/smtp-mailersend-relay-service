const { SMTPServer } = require('smtp-server');
const simpleParser = require('mailparser').simpleParser;
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');
const { MailerSend, EmailParams, Recipient, Attachment, Sender } = require('mailersend');

// Load environment variables
dotenv.config();

// Configuration
const config = {
  smtp: {
    port: process.env.SMTP_PORT || 2525,
    host: '127.0.0.1', // Only listen on localhost/loopback interface
    // No authentication needed since it's only accessible locally
  },
  mailersend: {
    apiKey: process.env.MAILERSEND_API_KEY,
  },
  attachmentDir: process.env.ATTACHMENT_DIR || path.join(__dirname, 'attachments')
};

// Ensure attachment directory exists
if (!fs.existsSync(config.attachmentDir)) {
  fs.mkdirSync(config.attachmentDir, { recursive: true });
}

const mailersend = new MailerSend({
  apiKey: config.mailersend.apiKey,
});

// Initialize SMTP server
const smtpServer = new SMTPServer({
  secure: false,
  authOptional: true, // No auth required
  disabledCommands: ['STARTTLS'], // No need for TLS on localhost-only connection
  onData(stream, session, callback) {
    let mailData = '';
    stream.on('data', (chunk) => {
      mailData += chunk;
    });

    stream.on('end', async () => {
      try {
        // Parse the email
        const parsedMail = await simpleParser(mailData);
        
        console.log('Received email:');
        console.log(`From: ${parsedMail.from?.text}`);
        console.log(`To: ${parsedMail.to?.text}`);
        console.log(`Subject: ${parsedMail.subject}`);
        
        // Process the email with MailerSend
        await sendViaMailerSend(parsedMail);
        
        callback();
      } catch (error) {
        console.error('Error processing email:', error);
        callback(new Error('Error processing mail'));
      }
    });
  }
});

// Start SMTP server
smtpServer.listen(config.smtp.port, config.smtp.host, () => {
  console.log(`SMTP Server listening on ${config.smtp.host}:${config.smtp.port} (localhost only)`);
});

// Helper function to save attachment to disk
async function saveAttachment(attachment) {
  const filename = `${Date.now()}-${attachment.filename}`;
  const filepath = path.join(config.attachmentDir, filename);
  
  await fs.promises.writeFile(filepath, attachment.content);
  
  return {
    filename: attachment.filename,
    filepath,
    content: attachment.content,
    contentType: attachment.contentType
  };
}

/**
 * 
 * @param {import('mailparser').ParsedMail} parsedMail 
 * @returns 
 */  
async function sendViaMailerSend(parsedMail) {
  try {
    // Extract email addresses
    const from = parsedMail.from.value[0];
    
    // Create recipients (To)
    const recipients = parsedMail.to.value.map(recipient => 
      new Recipient(recipient.address, recipient.name || '')
    );
    
    // Create a new EmailParams instance
    const emailParams = new EmailParams()
      .setFrom(new Sender(from.address, from.name || ''))
      .setTo(recipients)
      .setSubject(parsedMail.subject || '(No Subject)');
    
    // Set email content
    if (parsedMail.html) {
      emailParams.setHtml(parsedMail.html);
    }
    if (parsedMail.text) {
      emailParams.setText(parsedMail.text);
    }
    
    // Add CC if present
    if (parsedMail.cc && parsedMail.cc.value.length > 0) {
      const ccRecipients = parsedMail.cc.value.map(recipient => 
        new Recipient(recipient.address, recipient.name || '')
      );
      emailParams.setCc(ccRecipients);
    }
    
    // Add BCC if present
    if (parsedMail.bcc && parsedMail.bcc.value.length > 0) {
      const bccRecipients = parsedMail.bcc.value.map(recipient => 
        new Recipient(recipient.address, recipient.name || '')
      );
      emailParams.setBcc(bccRecipients);
    }
    
    // Add Reply-To if present
    if (parsedMail.replyTo && parsedMail.replyTo.value.length > 0) {
      const replyTo = parsedMail.replyTo.value[0];
      emailParams.setReplyTo(new Recipient(replyTo.address, replyTo.name));
    }
    
    // Process attachments if any
    if (parsedMail.attachments && parsedMail.attachments.length > 0) {
      const attachments = [];
      
      for (const attachment of parsedMail.attachments) {
        const savedAttachment = await saveAttachment(attachment);
        
        attachments.push(
          new Attachment(
            savedAttachment.content.toString('base64'),
            savedAttachment.filename,
            'attachment'
          )
        );
      }
      
      emailParams.setAttachments(attachments);
    }
    
    // Send the email
    try {
      const response = await mailersend.email.send(emailParams);
      console.log('Email sent successfully via MailerSend:', response);
      return response;
    } catch (error) {
      console.error('Error from MailerSend API:', error.body || error);
      throw error;
    }
  } catch (error) {
    console.error('Error preparing email for MailerSend:', error);
    throw error;
  }
}

// Handle graceful shutdown
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

function shutdown() {
  console.log('Shutting down server...');
  
  smtpServer.close(() => {
    console.log('SMTP server closed');
    process.exit(0);
  });
}

// Log startup info
console.log('SMTP to MailerSend Relay Service');
console.log('--------------------------------');
console.log(`SMTP server running on ${config.smtp.host}:${config.smtp.port} (localhost only)`);
console.log('Authentication: Disabled (localhost only)');
console.log(`MailerSend API key configured: ${Boolean(config.mailersend.apiKey)}`);
console.log(`Attachments directory: ${config.attachmentDir}`);
console.log('');
console.log('Use systemctl status smtp-mailersend to check service status');
console.log('Use journalctl -u smtp-mailersend -f to view logs');