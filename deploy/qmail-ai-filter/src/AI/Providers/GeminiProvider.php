<?php

namespace QmailAiFilter\AI\Providers;

use QmailAiFilter\AI\AIProviderInterface;

class GeminiProvider implements AIProviderInterface
{
    private $config;

    public function __construct(array $config)
    {
        $this->config = $config;
    }

    public function getProviderName(): string
    {
        return 'Google Gemini';
    }

    public function isConfigured(): bool
    {
        return !empty($this->config['gemini']['api_key']);
    }

    public function analyzeEmail(array $emailData): array
    {
        $apiKey = $this->config['gemini']['api_key'];
        $model  = $this->config['gemini']['model'] ?? 'gemini-1.5-flash';
        $url    = "https://generativelanguage.googleapis.com/v1beta/models/{$model}:generateContent?key={$apiKey}";

        $prompt = $this->buildSpamAnalysisPrompt($emailData);

        $payload = json_encode([
            'contents' => [['parts' => [['text' => $prompt]]]],
            'generationConfig' => ['temperature' => 0.3, 'maxOutputTokens' => 500],
        ]);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $payload,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $this->config['spam_detection']['api_timeout'] ?? 30,
            CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
        ]);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($response === false || $httpCode !== 200) {
            throw new \RuntimeException("Gemini API error (HTTP {$httpCode})");
        }

        $body = json_decode($response, true);
        $text = $body['candidates'][0]['content']['parts'][0]['text'] ?? '';

        $result = $this->parseResponse($text);

        $usage = $body['usageMetadata'] ?? [];
        $result['model']             = $model;
        $result['prompt_tokens']     = (int)($usage['promptTokenCount'] ?? 0);
        $result['completion_tokens'] = (int)($usage['candidatesTokenCount'] ?? 0);
        $result['total_tokens']      = (int)($usage['totalTokenCount'] ?? $result['prompt_tokens'] + $result['completion_tokens']);

        return $result;
    }

    private function buildSpamAnalysisPrompt(array $emailData): string
    {
        $subject     = substr($emailData['subject'] ?? '', 0, 200);
        $from        = $emailData['from'] ?? '';
        $body        = substr($emailData['body'] ?? '', 0, 2000);
        $hasAttach   = $emailData['has_attachments'] ? 'yes' : 'no';
        $urlCount    = count($emailData['urls'] ?? []);

        return <<<PROMPT
Analyze this email and determine if it is spam. Return ONLY valid JSON.

Subject: {$subject}
From: {$from}
Has Attachments: {$hasAttach}
URL Count: {$urlCount}
Body (first 2000 chars):
{$body}

Return JSON with these fields:
- is_spam: boolean
- confidence: float 0.0-1.0
- reason: string (brief explanation)
- spam_type: one of "phishing","scam","malware","marketing","other","none"

JSON only, no markdown:
PROMPT;
    }

    private function parseResponse(string $text): array
    {
        // Strip markdown code fences if present
        $text = preg_replace('/```(?:json)?\s*/i', '', $text);
        $text = trim($text, " \t\n\r`");

        $result = json_decode($text, true);
        if (!is_array($result)) {
            return ['is_spam' => false, 'confidence' => 0.0, 'reason' => 'Parse error', 'spam_type' => 'none'];
        }
        return [
            'is_spam'    => (bool)($result['is_spam'] ?? false),
            'confidence' => (float)($result['confidence'] ?? 0.0),
            'reason'     => (string)($result['reason'] ?? ''),
            'spam_type'  => (string)($result['spam_type'] ?? 'none'),
        ];
    }
}
