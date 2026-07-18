#!/usr/bin/env php
<?php
/**
 * QMAIL AI Filter - Synchronous Filter
 * 
 * This script performs immediate AI spam analysis for email filtering.
 * Called by the wrapper script for real-time decision making.
 * 
 * Usage: php sync-filter.php <email-path> <recipient-email>
 * Output: JSON with is_spam, confidence, reason
 */

// Auto-detect installation directory
$installDir = dirname(__DIR__);

try {
    // Load autoloader
    require_once $installDir . '/src/Autoloader.php';
    Autoloader::register();
    
    // Load config
    $config = require $installDir . '/config/config.php';
    
    // Get command line arguments
    $emailPath = $argv[1] ?? null;
    $recipientEmail = $argv[2] ?? null;
    
    if (!$emailPath || !file_exists($emailPath)) {
        echo json_encode(['error' => 'Email file not found', 'is_spam' => false]);
        exit(1);
    }
    
    if (!$recipientEmail) {
        echo json_encode(['error' => 'Recipient email required', 'is_spam' => false]);
        exit(1);
    }
    
    // Initialize logger
    $logger = new \QmailAiFilter\Logging\Logger(
        $config['logging']['log_dir'],
        $config['logging']['level']
    );
    
    $logger->info("Synchronous filter called", [
        'email_path' => $emailPath,
        'recipient' => $recipientEmail
    ]);
    
    // Parse email
    $emailParser = new \QmailAiFilter\Email\EmailParser($emailPath, $logger);
    $emailData = $emailParser->getEmailData();

    // ── Whitelist check — bypass AI entirely for trusted senders ─────────────
    $whitelistFile = $installDir . '/config/whitelist.json';
    if (file_exists($whitelistFile)) {
        $wl = json_decode(file_get_contents($whitelistFile), true) ?: [];

        $rawFrom = $emailData['from'] ?? '';
        // Extract bare email from "Name <email>" format
        if (preg_match('/<([^>@\s]+@[^>]+)>/', $rawFrom, $fm)) {
            $senderEmail = strtolower(trim($fm[1]));
        } else {
            $senderEmail = strtolower(trim(preg_replace('/\s+.*$/', '', $rawFrom)));
        }
        $senderDomain = '';
        $atPos = strrpos($senderEmail, '@');
        if ($atPos !== false) $senderDomain = substr($senderEmail, $atPos + 1);

        $recipientLc  = strtolower($recipientEmail);
        $atPos2 = strrpos($recipientLc, '@');
        $recipientDomain = $atPos2 !== false ? substr($recipientLc, $atPos2 + 1) : '';

        $isWhitelisted = false;
        // Global
        if (!$isWhitelisted && $senderEmail && in_array($senderEmail, $wl['global']['emails'] ?? [])) $isWhitelisted = true;
        if (!$isWhitelisted && $senderDomain && in_array($senderDomain, $wl['global']['domains'] ?? [])) $isWhitelisted = true;
        // Domain-level
        if (!$isWhitelisted && $recipientDomain) {
            if ($senderEmail && in_array($senderEmail, $wl['domains'][$recipientDomain]['emails'] ?? [])) $isWhitelisted = true;
            if ($senderDomain && in_array($senderDomain, $wl['domains'][$recipientDomain]['domains'] ?? [])) $isWhitelisted = true;
        }
        // User-level
        if (!$isWhitelisted) {
            if ($senderEmail && in_array($senderEmail, $wl['users'][$recipientLc]['emails'] ?? [])) $isWhitelisted = true;
            if ($senderDomain && in_array($senderDomain, $wl['users'][$recipientLc]['domains'] ?? [])) $isWhitelisted = true;
        }

        if ($isWhitelisted) {
            $logger->info("Sender whitelisted — skipping AI", ['sender' => $senderEmail, 'recipient' => $recipientEmail]);
            // Write a stats entry (confidence 0 = whitelisted ham)
            $statsFile = $config['stats']['stats_file'] ?? ($installDir . '/stats/stats.jsonl');
            $parts = explode('@', $recipientEmail, 2);
            @file_put_contents($statsFile, json_encode([
                'ts' => time(), 'domain' => $parts[1] ?? $recipientEmail,
                'account' => $recipientEmail, 'is_spam' => false,
                'confidence' => 0.0, 'spam_type' => 'whitelisted',
            ]) . "\n", FILE_APPEND | LOCK_EX);

            echo json_encode(['is_spam' => false, 'confidence' => 0.0, 'reason' => 'Whitelisted sender', 'spam_type' => 'whitelisted']);
            exit(0);
        }
    }

    // Initialize AI provider
    $providerName = $config['ai_provider']['provider'];
    $aiProvider = null;
    
    if ($providerName === 'github_copilot') {
        $apiKey = $config['ai_provider']['github_copilot']['api_key'] ?? '';
        $model = $config['ai_provider']['github_copilot']['model'] ?? 'gpt-4o';
        
        $aiProvider = new \QmailAiFilter\AI\Providers\GitHubCopilotProvider(
            $apiKey,
            $model,
            $logger,
            $config['spam_detection']['api_timeout'] ?? 30
        );
    } elseif ($providerName === 'openai') {
        $apiKey = $config['ai_provider']['openai']['api_key'] ?? '';
        $model = $config['ai_provider']['openai']['model'] ?? 'gpt-3.5-turbo';
        
        $aiProvider = new \QmailAiFilter\AI\Providers\OpenAIProvider(
            $apiKey,
            $model,
            $logger,
            $config['spam_detection']['api_timeout'] ?? 30
        );
    } elseif ($providerName === 'claude' || $providerName === 'claude_anthropic') {
        $apiKey = $config['ai_provider']['claude_anthropic']['api_key'] ?? '';
        $model = $config['ai_provider']['claude_anthropic']['model'] ?? 'claude-3-haiku-20240307';
        
        $aiProvider = new \QmailAiFilter\AI\Providers\ClaudeProvider(
            $apiKey,
            $model,
            $logger,
            $config['spam_detection']['api_timeout'] ?? 30
        );
    } elseif ($providerName === 'ollama-cloud') {
        $apiKey = $config['ai_provider']['ollama-cloud']['api_key'] ?? '';
        $model = $config['ai_provider']['ollama-cloud']['model'] ?? 'glm-5.1';

        $aiProvider = new \QmailAiFilter\AI\Providers\OllamaCloudProvider(
            $apiKey,
            $model,
            $logger,
            $config['spam_detection']['api_timeout'] ?? 30
        );
    } elseif ($providerName === 'gemini') {
        $aiProvider = new \QmailAiFilter\AI\Providers\GeminiProvider($config['ai_provider']);
    }

    if (!$aiProvider || !$aiProvider->isConfigured()) {
        $logger->error("AI provider not configured: {$providerName}");
        echo json_encode(['error' => 'AI provider not configured', 'is_spam' => false]);
        exit(1);
    }

    // Analyze email
    $result = $aiProvider->analyzeEmail($emailData);

    // Apply confidence threshold
    $threshold = $config['spam_detection']['confidence_threshold'];
    $isSpam = $result['is_spam'] && $result['confidence'] >= $threshold;

    // Write stats entry for SysAdminHCP dashboard
    $statsFile = $config['stats']['stats_file'] ?? ($installDir . '/stats/stats.jsonl');
    $parts = explode('@', $recipientEmail, 2);
    $statsDomain = $parts[1] ?? $recipientEmail;
    $statsEntry = json_encode([
        'ts'         => time(),
        'domain'     => $statsDomain,
        'account'    => $recipientEmail,
        'is_spam'    => $isSpam,
        'confidence' => round((float)($result['confidence'] ?? 0), 4),
        'spam_type'  => $result['spam_type'] ?? 'none',
    ]) . "\n";
    @file_put_contents($statsFile, $statsEntry, FILE_APPEND | LOCK_EX);

    // Write token usage entry for AI Token Usage dashboard
    $tokenUsageFile = $config['stats']['token_usage_file'] ?? ($installDir . '/stats/token-usage.jsonl');
    // Fall back to the configured model name, not the provider key
    $configuredModel = $config['ai_provider'][$providerName]['model'] ?? $providerName;
    $tokenEntry = json_encode([
        'ts'               => time(),
        'provider'         => $aiProvider->getProviderName(),
        'model'            => $result['model'] ?? $configuredModel,
        'domain'           => $statsDomain,
        'prompt_tokens'    => (int)($result['prompt_tokens'] ?? 0),
        'completion_tokens'=> (int)($result['completion_tokens'] ?? 0),
        'total_tokens'     => (int)($result['total_tokens'] ?? (($result['prompt_tokens'] ?? 0) + ($result['completion_tokens'] ?? 0))),
    ]) . "\n";
    @file_put_contents($tokenUsageFile, $tokenEntry, FILE_APPEND | LOCK_EX);

    // Log result
    $logger->info("Synchronous filter result", [
        'recipient' => $recipientEmail,
        'is_spam' => $isSpam,
        'confidence' => $result['confidence'],
        'reason' => $result['reason']
    ]);

    // Output JSON result
    echo json_encode([
        'is_spam' => $isSpam,
        'confidence' => $result['confidence'],
        'reason' => $result['reason'],
        'spam_type' => $result['spam_type'] ?? 'unknown'
    ]);

    exit(0);
    
} catch (Throwable $e) {
    if (isset($logger)) {
        $logger->error("Sync filter error: " . $e->getMessage());
    }
    // On error, default to allowing email (fail open)
    echo json_encode(['error' => $e->getMessage(), 'is_spam' => false]);
    exit(1);
}
