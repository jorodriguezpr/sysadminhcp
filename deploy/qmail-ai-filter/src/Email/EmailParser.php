<?php
/**
 * QMAIL AI Filter - Email Parser
 * 
 * Extracts and parses email data for AI analysis
 * 
 * @package    QmailAiFilter\Email
 * @author     Jose Rodriguez Arroyo <jrpcone@gmail.com>
 * @copyright  2026 Jose Rodriguez Arroyo
 * @license    MIT License
 * @link       https://github.com/jorodriguezpr/qmail-ai-filter
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

namespace QmailAiFilter\Email;

class EmailParser
{
    private $emailPath;
    private $headers = [];
    private $body = '';
    private $attachments = [];
    private $urls = [];
    
    public function __construct(string $emailPath)
    {
        $this->emailPath = $emailPath;
        $this->parse();
    }
    
    /**
     * Parse email file
     */
    private function parse(): void
    {
        if (!file_exists($this->emailPath)) {
            throw new \Exception("Email file not found: {$this->emailPath}");
        }
        
        $content = file_get_contents($this->emailPath);
        
        // Split headers and body
        $parts = explode("\n\n", $content, 2);
        $headerSection = $parts[0] ?? '';
        $bodySection = $parts[1] ?? '';
        
        $this->parseHeaders($headerSection);
        $this->parseBody($bodySection);
        $this->extractUrls();
    }
    
    /**
     * Parse email headers
     */
    private function parseHeaders(string $headerSection): void
    {
        $lines = explode("\n", $headerSection);
        $currentHeader = '';
        $currentValue = '';
        
        foreach ($lines as $line) {
            // Continuation of previous header
            if (preg_match('/^\s/', $line)) {
                $currentValue .= ' ' . trim($line);
            } else {
                // New header
                if (!empty($currentHeader)) {
                    $this->headers[$currentHeader] = trim($currentValue);
                }
                
                if (strpos($line, ':') !== false) {
                    [$currentHeader, $currentValue] = explode(':', $line, 2);
                    $currentHeader = strtolower(trim($currentHeader));
                }
            }
        }
        
        // Add last header
        if (!empty($currentHeader)) {
            $this->headers[$currentHeader] = trim($currentValue);
        }
    }
    
    /**
     * Parse email body
     */
    private function parseBody(string $bodySection): void
    {
        // Check for multipart
        $contentType = $this->headers['content-type'] ?? '';
        
        if (stripos($contentType, 'multipart') !== false) {
            $this->parseMultipart($bodySection, $contentType);
        } else {
            $this->body = $this->decodeBody($bodySection, $contentType);
        }
    }
    
    /**
     * Parse multipart email
     */
    private function parseMultipart(string $bodySection, string $contentType): void
    {
        // Extract boundary
        if (!preg_match('/boundary="?([^";]+)"?/i', $contentType, $matches)) {
            $this->body = $bodySection;
            return;
        }
        
        $boundary = $matches[1];
        $parts = explode("--{$boundary}", $bodySection);
        
        foreach ($parts as $part) {
            if (empty(trim($part)) || strpos($part, '--') === 0) {
                continue;
            }
            
            [$partHeaders, $partBody] = explode("\n\n", $part, 2);
            
            if (stripos($partHeaders, 'text/plain') !== false || stripos($partHeaders, 'text/html') !== false) {
                $this->body .= $this->decodeBody($partBody, $partHeaders);
            } elseif (stripos($partHeaders, 'attachment') !== false) {
                $this->parseAttachment($partHeaders, $partBody);
            }
        }
    }
    
    /**
     * Parse email attachment
     */
    private function parseAttachment(string $headers, string $body): void
    {
        if (preg_match('/filename="?([^";]+)"?/i', $headers, $matches)) {
            $filename = $matches[1];
            $this->attachments[] = [
                'filename' => $filename,
                'size' => strlen($body),
                'mime_type' => $this->extractMimeType($headers),
            ];
        }
    }
    
    /**
     * Decode email body based on encoding
     */
    private function decodeBody(string $body, string $headers): string
    {
        $encoding = $headers;
        
        if (stripos($encoding, 'quoted-printable') !== false) {
            $body = quoted_printable_decode($body);
        } elseif (stripos($encoding, 'base64') !== false) {
            $body = base64_decode($body);
        }
        
        return trim($body);
    }
    
    /**
     * Extract URLs from email body
     */
    private function extractUrls(): void
    {
        // Simple URL regex
        preg_match_all('#https?://[^\s<>"{}|\\^`\[\]]*#i', $this->body, $matches);
        $this->urls = $matches[0] ?? [];
    }
    
    /**
     * Extract MIME type from headers
     */
    private function extractMimeType(string $headers): string
    {
        if (preg_match('/Content-Type:\s*([^;]+)/i', $headers, $matches)) {
            return trim($matches[1]);
        }
        return 'application/octet-stream';
    }
    
    /**
     * Get parsed email data
     */
    public function getEmailData(): array
    {
        return [
            'subject' => $this->headers['subject'] ?? '[No Subject]',
            'from' => $this->headers['from'] ?? '[Unknown]',
            'to' => $this->headers['to'] ?? '',
            'date' => $this->headers['date'] ?? '',
            'body' => substr($this->body, 0, 5000), // Limit body
            'headers' => $this->headers,
            'attachments' => $this->attachments,
            'urls' => $this->urls,
            'has_attachments' => !empty($this->attachments),
            'has_urls' => !empty($this->urls),
        ];
    }
    
    public function getHeaders(): array
    {
        return $this->headers;
    }
    
    public function getBody(): string
    {
        return $this->body;
    }
    
    public function getAttachments(): array
    {
        return $this->attachments;
    }
    
    public function getUrls(): array
    {
        return $this->urls;
    }
}
