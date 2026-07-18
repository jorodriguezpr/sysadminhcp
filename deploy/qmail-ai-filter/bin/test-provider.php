#!/usr/bin/env php
<?php
/**
 * Test AI provider connectivity — called by SysAdminHCP panel.
 * Outputs JSON: {"success": true/false, "provider": "...", "message": "..."}
 */

$installDir = dirname(__DIR__);
require_once $installDir . '/src/Autoloader.php';
Autoloader::register();
$config = require $installDir . '/config/config.php';

$providerName = $config['ai_provider']['provider'];
$timeout = $config['spam_detection']['api_timeout'] ?? 30;

// Minimal test email data
$testEmail = [
    'subject'         => 'Test connection',
    'from'            => 'test@example.com',
    'to'              => 'admin@localhost',
    'body'            => 'This is a test email to verify AI provider connectivity.',
    'headers'         => [],
    'attachments'     => [],
    'urls'            => [],
    'has_attachments' => false,
    'has_urls'        => false,
];

try {
    $logger = new \QmailAiFilter\Logging\Logger($config['logging']['log_dir'], 'error');

    $provider = null;
    switch ($providerName) {
        case 'openai':
            $provider = new \QmailAiFilter\AI\Providers\OpenAIProvider(
                $config['ai_provider']['openai']['api_key'], $config['ai_provider']['openai']['model'], $logger, $timeout);
            break;
        case 'claude_anthropic':
            $provider = new \QmailAiFilter\AI\Providers\ClaudeProvider(
                $config['ai_provider']['claude_anthropic']['api_key'], $config['ai_provider']['claude_anthropic']['model'], $logger, $timeout);
            break;
        case 'ollama-cloud':
            $provider = new \QmailAiFilter\AI\Providers\OllamaCloudProvider(
                $config['ai_provider']['ollama-cloud']['api_key'], $config['ai_provider']['ollama-cloud']['model'], $logger, $timeout);
            break;
        case 'gemini':
            $provider = new \QmailAiFilter\AI\Providers\GeminiProvider($config['ai_provider']);
            break;
        default:
            echo json_encode(['success' => false, 'provider' => $providerName, 'message' => "Unknown provider: $providerName"]);
            exit(1);
    }

    if (!$provider->isConfigured()) {
        echo json_encode(['success' => false, 'provider' => $provider->getProviderName(), 'message' => 'API key not configured']);
        exit(1);
    }

    $result = $provider->analyzeEmail($testEmail);
    echo json_encode([
        'success'    => true,
        'provider'   => $provider->getProviderName(),
        'message'    => 'connected',
        'test_result' => ['is_spam' => $result['is_spam'], 'confidence' => $result['confidence']],
    ]);
    exit(0);

} catch (Throwable $e) {
    echo json_encode(['success' => false, 'provider' => $providerName, 'message' => $e->getMessage()]);
    exit(1);
}
