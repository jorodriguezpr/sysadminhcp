<?php
/**
 * QMAIL AI Filter - Ollama Cloud Provider
 *
 * Uses Ollama Cloud API models to analyze emails for spam.
 *
 * @package    QmailAiFilter\AI\Providers
 */

namespace QmailAiFilter\AI\Providers;

use QmailAiFilter\AI\AIProviderInterface;
use QmailAiFilter\Logging\Logger;

class OllamaCloudProvider implements AIProviderInterface
{
    private $apiKey;
    private $apiUrl;
    private $model;
    private $logger;
    private $timeout;

    public function __construct(string $apiKey, string $model = 'glm-5.1', Logger $logger = null, int $timeout = 30)
    {
        $this->apiKey = $apiKey;
        $this->model = $model;
        $this->apiUrl = 'https://ollama.com/api/chat';
        $this->logger = $logger ?? new Logger();
        $this->timeout = $timeout;
    }

    public function analyzeEmail(array $emailData): array
    {
        if (!$this->isConfigured()) {
            return [
                'is_spam' => false,
                'confidence' => 0,
                'reason' => 'Ollama Cloud provider not configured',
                'error' => true,
            ];
        }

        try {
            $prompt = $this->buildSpamAnalysisPrompt($emailData);
            $response = $this->callOllamaCloudAPI($prompt);

            return $this->parseResponse($response);
        } catch (\Exception $e) {
            $this->logger->error('Ollama Cloud API error: ' . $e->getMessage());
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
        return 'Ollama Cloud';
    }

    private function buildSpamAnalysisPrompt(array $emailData): string
    {
        $subject = $emailData['subject'] ?? '';
        $from = $emailData['from'] ?? '';
        $body = substr($emailData['body'] ?? '', 0, 2000);
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

    private function callOllamaCloudAPI(string $prompt): array
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
            'stream' => false,
            'options' => [
                'temperature' => 0.3,
            ],
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
            $errorMsg = "Ollama Cloud API failed: HTTP {$httpCode}";
            if ($error) {
                $errorMsg .= ", cURL Error: {$error}";
            }
            if ($response) {
                $errorMsg .= ", Response: " . substr($response, 0, 200);
            }
            throw new \Exception($errorMsg);
        }

        return json_decode($response, true) ?? [];
    }

    private function parseResponse(array $response): array
    {
        // Extract model name and token counts BEFORE content parsing so they always survive
        $modelName        = $response['model'] ?? $this->model;
        $promptTokens     = (int)($response['usage']['prompt_tokens']     ?? $response['prompt_eval_count'] ?? 0);
        $completionTokens = (int)($response['usage']['completion_tokens'] ?? $response['eval_count']        ?? 0);
        $totalTokens      = (int)($response['usage']['total_tokens']      ?? $promptTokens + $completionTokens);

        try {
            $content = $response['message']['content']
                ?? ($response['choices'][0]['message']['content'] ?? '');

            // Find the first complete JSON object in the content — handles extra text, code fences, etc.
            $jsonStr = $this->extractJsonObject($content);
            if ($jsonStr === null) {
                throw new \Exception('No JSON object found in response: ' . substr($content, 0, 120));
            }

            $analysis = json_decode($jsonStr, true);
            if (!$analysis || !isset($analysis['is_spam'])) {
                throw new \Exception('Invalid JSON — missing is_spam: ' . substr($jsonStr, 0, 120));
            }

            return [
                'is_spam'          => (bool)($analysis['is_spam'] ?? false),
                'confidence'       => (float)($analysis['confidence'] ?? 0.0),
                'reason'           => $analysis['reason'] ?? 'No reason provided',
                'spam_type'        => $analysis['spam_type'] ?? 'unknown',
                'model'            => $modelName,
                'prompt_tokens'    => $promptTokens,
                'completion_tokens'=> $completionTokens,
                'total_tokens'     => $totalTokens,
            ];
        } catch (\Exception $e) {
            $this->logger->error('Failed to parse Ollama Cloud response: ' . $e->getMessage());
            // Return model and token counts even on content-parse failure
            return [
                'is_spam'          => false,
                'confidence'       => 0.0,
                'reason'           => 'Failed to parse response',
                'model'            => $modelName,
                'prompt_tokens'    => $promptTokens,
                'completion_tokens'=> $completionTokens,
                'total_tokens'     => $totalTokens,
                'error'            => true,
            ];
        }
    }

    /** Find the first complete, balanced JSON object in an arbitrary string. */
    private function extractJsonObject(string $content): ?string
    {
        $start = strpos($content, '{');
        if ($start === false) return null;

        $depth    = 0;
        $inString = false;
        $escape   = false;
        $len      = strlen($content);

        for ($i = $start; $i < $len; $i++) {
            $c = $content[$i];
            if ($escape)              { $escape = false; continue; }
            if ($c === '\\' && $inString) { $escape = true;  continue; }
            if ($c === '"')           { $inString = !$inString; continue; }
            if ($inString)            { continue; }
            if ($c === '{')           { $depth++; }
            elseif ($c === '}')       {
                $depth--;
                if ($depth === 0) return substr($content, $start, $i - $start + 1);
            }
        }
        return null;
    }
}