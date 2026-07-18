<?php
/**
 * QMAIL AI Filter - OpenAI Provider
 * 
 * Uses OpenAI's GPT models to analyze emails for spam
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

class OpenAIProvider implements AIProviderInterface
{
    private $apiKey;
    private $apiUrl;
    private $model;
    private $logger;
    private $timeout;
    
    public function __construct(string $apiKey, string $model = 'gpt-3.5-turbo', Logger $logger = null, int $timeout = 30)
    {
        $this->apiKey = $apiKey;
        $this->model = $model;
        $this->apiUrl = 'https://api.openai.com/v1/chat/completions';
        $this->logger = $logger ?? new Logger();
        $this->timeout = $timeout;
    }
    
    public function analyzeEmail(array $emailData): array
    {
        if (!$this->isConfigured()) {
            return [
                'is_spam' => false,
                'confidence' => 0,
                'reason' => 'OpenAI provider not configured',
                'error' => true,
            ];
        }
        
        try {
            $prompt = $this->buildSpamAnalysisPrompt($emailData);
            $response = $this->callOpenAIAPI($prompt);
            
            return $this->parseResponse($response);
        } catch (\Exception $e) {
            $this->logger->error('OpenAI API error: ' . $e->getMessage());
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
        return 'OpenAI';
    }
    
    /**
     * Build prompt for spam analysis
     */
    private function buildSpamAnalysisPrompt(array $emailData): string
    {
        $subject = $emailData['subject'] ?? '';
        $from = $emailData['from'] ?? '';
        $body = substr($emailData['body'] ?? '', 0, 2000); // Limit body length
        $hasAttachments = !empty($emailData['attachments']);
        $hasUrls = !empty($emailData['urls']);
        
        return <<<PROMPT
Analyze the following email for spam characteristics and respond with a JSON object only:

FROM: {$from}
SUBJECT: {$subject}
HAS_ATTACHMENTS: {$hasAttachments}
HAS_URLS: {$hasUrls}

EMAIL BODY:
{$body}

---

Analyze this email for spam indicators. Consider:
- Suspicious sender or domain
- Common spam keywords and patterns
- Urgency or threat-based language
- Phishing attempts
- Financial/banking scams
- Too-good-to-be-true offers
- Malicious links or attachments

Respond ONLY with valid JSON (no markdown, no code blocks):
{
  "is_spam": true/false,
  "confidence": 0.0-1.0,
  "reason": "brief explanation",
  "spam_type": "phishing|scam|malware|marketing|other|none"
}
PROMPT;
    }
    
    /**
     * Call OpenAI API
     */
    private function callOpenAIAPI(string $prompt): array
    {
        $payload = [
            'model' => $this->model,
            'messages' => [
                [
                    'role' => 'system',
                    'content' => 'You are a spam detection expert. Analyze emails and respond only with JSON.',
                ],
                [
                    'role' => 'user',
                    'content' => $prompt,
                ],
            ],
            'temperature' => 0.3,
            'max_tokens' => 500,
        ];
        
        $ch = curl_init($this->apiUrl);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $this->apiKey,
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
            throw new \Exception("OpenAI API failed: HTTP {$httpCode}, {$error}");
        }
        
        return json_decode($response, true) ?? [];
    }
    
    /**
     * Parse OpenAI response
     */
    private function parseResponse(array $response): array
    {
        try {
            $content = $response['choices'][0]['message']['content'] ?? '';
            
            // Clean JSON response (remove markdown code blocks if present)
            $content = preg_replace('/^```json\s*|\s*```$/m', '', $content);
            $analysis = json_decode($content, true);
            
            if (!$analysis) {
                throw new \Exception('Invalid JSON response');
            }
            
            $promptTokens     = (int)($response['usage']['prompt_tokens'] ?? 0);
            $completionTokens = (int)($response['usage']['completion_tokens'] ?? 0);
            $totalTokens      = (int)($response['usage']['total_tokens'] ?? $promptTokens + $completionTokens);

            return [
                'is_spam'          => (bool)($analysis['is_spam'] ?? false),
                'confidence'       => (float)($analysis['confidence'] ?? 0.0),
                'reason'           => $analysis['reason'] ?? 'No reason provided',
                'spam_type'        => $analysis['spam_type'] ?? 'unknown',
                'model'            => $this->model,
                'prompt_tokens'    => $promptTokens,
                'completion_tokens'=> $completionTokens,
                'total_tokens'     => $totalTokens,
            ];
        } catch (\Exception $e) {
            $this->logger->error('Failed to parse OpenAI response: ' . $e->getMessage());
            return [
                'is_spam' => false,
                'confidence' => 0,
                'reason' => 'Failed to parse response',
                'error' => true,
            ];
        }
    }
}
