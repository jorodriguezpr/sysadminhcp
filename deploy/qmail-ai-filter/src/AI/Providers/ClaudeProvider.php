<?php
/**
 * QMAIL AI Filter - Claude Anthropic Provider
 * 
 * Uses Claude AI to analyze emails for spam
 * 
 * @package    QmailAiFilter\AI\Providers
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

namespace QmailAiFilter\AI\Providers;

use QmailAiFilter\AI\AIProviderInterface;
use QmailAiFilter\Logging\Logger;

class ClaudeProvider implements AIProviderInterface
{
    private $apiKey;
    private $apiUrl;
    private $model;
    private $logger;
    private $timeout;
    
    public function __construct(string $apiKey, string $model = 'claude-3-haiku-20240307', Logger $logger = null, int $timeout = 30)
    {
        $this->apiKey = $apiKey;
        $this->model = $model;
        $this->apiUrl = 'https://api.anthropic.com/v1/messages';
        $this->logger = $logger ?? new Logger();
        $this->timeout = $timeout;
    }
    
    public function analyzeEmail(array $emailData): array
    {
        if (!$this->isConfigured()) {
            return [
                'is_spam' => false,
                'confidence' => 0,
                'reason' => 'Claude provider not configured',
                'error' => true,
            ];
        }
        
        try {
            $prompt = $this->buildSpamAnalysisPrompt($emailData);
            $response = $this->callClaudeAPI($prompt);
            
            return $this->parseResponse($response);
        } catch (\Exception $e) {
            $this->logger->error('Claude API error: ' . $e->getMessage());
            return [
                'is_spam' => false,
                'confidence' => 0,
                'reason' => 'Error analyzing email',
                'error' => true,
            ];
        }
    }
    
    public function isConfigured(): bool
    {
        return !empty($this->apiKey);
    }
    
    public function getProviderName(): string
    {
        return 'Claude';
    }
    
    /**
     * Build prompt for spam analysis
     */
    private function buildSpamAnalysisPrompt(array $emailData): string
    {
        $subject = $emailData['subject'] ?? '';
        $from = $emailData['from'] ?? '';
        $body = substr($emailData['body'] ?? '', 0, 2000);
        $hasAttachments = !empty($emailData['attachments']);
        $hasUrls = !empty($emailData['urls']);
        
        return <<<PROMPT
Analyze the following email for spam characteristics:

FROM: {$from}
SUBJECT: {$subject}
HAS_ATTACHMENTS: {$hasAttachments}
HAS_URLS: {$hasUrls}

EMAIL BODY:
{$body}

---

Respond with ONLY a JSON object (no other text):
{
  "is_spam": true/false,
  "confidence": 0.0-1.0,
  "reason": "brief explanation",
  "spam_type": "phishing|scam|malware|marketing|other|none"
}
PROMPT;
    }
    
    /**
     * Call Claude API
     */
    private function callClaudeAPI(string $prompt): array
    {
        $payload = [
            'model' => $this->model,
            'max_tokens' => 500,
            'messages' => [
                [
                    'role' => 'user',
                    'content' => $prompt,
                ],
            ],
            'system' => 'You are a spam detection expert. Analyze emails for spam indicators. Respond only with valid JSON.',
        ];
        
        $ch = curl_init($this->apiUrl);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'x-api-key: ' . $this->apiKey,
                'anthropic-version: 2023-06-01',
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_TIMEOUT => $this->timeout,
            CURLOPT_SSL_VERIFYPEER => true,
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        
        if ($error || $httpCode !== 200) {
            throw new \Exception("Claude API failed: HTTP {$httpCode}, {$error}");
        }
        
        return json_decode($response, true) ?? [];
    }
    
    /**
     * Parse Claude response
     */
    private function parseResponse(array $response): array
    {
        try {
            $content = $response['content'][0]['text'] ?? '';
            
            // Clean JSON response
            $content = preg_replace('/^```json\s*|\s*```$/m', '', $content);
            $analysis = json_decode($content, true);
            
            if (!$analysis) {
                throw new \Exception('Invalid JSON response');
            }
            
            $promptTokens     = (int)($response['usage']['input_tokens'] ?? 0);
            $completionTokens = (int)($response['usage']['output_tokens'] ?? 0);

            return [
                'is_spam'          => (bool)($analysis['is_spam'] ?? false),
                'confidence'       => (float)($analysis['confidence'] ?? 0.0),
                'reason'           => $analysis['reason'] ?? 'No reason provided',
                'spam_type'        => $analysis['spam_type'] ?? 'unknown',
                'model'            => $this->model,
                'prompt_tokens'    => $promptTokens,
                'completion_tokens'=> $completionTokens,
                'total_tokens'     => $promptTokens + $completionTokens,
            ];
        } catch (\Exception $e) {
            $this->logger->error('Failed to parse Claude response: ' . $e->getMessage());
            return [
                'is_spam' => false,
                'confidence' => 0,
                'reason' => 'Failed to parse response',
                'error' => true,
            ];
        }
    }
}
