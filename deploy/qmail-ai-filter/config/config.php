<?php
/**
 * QMAIL AI Spam Filter - Configuration
 * 
 * This configuration file sets up the AI provider, API credentials,
 * and behavioral settings for the spam detection plugin.
 * 
 * All paths are dynamically determined based on installation user/directory.
 */

// Load .env file if it exists
loadEnvFile();

// Determine installation directory and user
$installUser = env('INSTALL_USER', 'admin');
$installDir = env('INSTALL_DIR', '');

// Auto-detect if not explicitly set
if (empty($installDir)) {
    $installDir = "/home/{$installUser}/qmail-ai-filter";
}

// Normalize path
$installDir = rtrim($installDir, '/');

// Verify installation directory exists
if (!is_dir($installDir)) {
    error_log("Warning: Installation directory not found: {$installDir}");
}

return [
    // Installation Configuration
    'installation' => [
        'install_user' => $installUser,
        'install_dir' => $installDir,
        'install_dir_short' => basename($installDir),
    ],
    
    // AI Provider Configuration
    'ai_provider' => [
        // Available: 'github_copilot' (recommended 2026+), 'openai', 'claude_anthropic', 'ollama-cloud'
        'provider' => env('AI_PROVIDER', 'github_copilot'),
        
        // GitHub Copilot (2026+ - RECOMMENDED)
        'github_copilot' => [
            'api_url' => 'https://api.github.com/copilot/chat/completions',
            'api_key' => env('GITHUB_COPILOT_API_KEY'),
            'model' => env('GITHUB_COPILOT_MODEL', 'gpt-4o'),
        ],
        
        // OpenAI API
        'openai' => [
            'api_url' => 'https://api.openai.com/v1/chat/completions',
            'api_key' => env('OPENAI_API_KEY'),
            'model' => env('OPENAI_MODEL', 'gpt-3.5-turbo'),
        ],
        
        // Claude Anthropic API
        'claude_anthropic' => [
            'api_url' => 'https://api.anthropic.com/v1/messages',
            'api_key' => env('CLAUDE_API_KEY'),
            'model' => env('CLAUDE_MODEL', 'claude-3-haiku-20240307'),
        ],

        // Ollama Cloud API
        'ollama-cloud' => [
            'api_url' => env('OLLAMA_CLOUD_API_URL', 'https://ollama.com/api/chat'),
            'api_key' => env('OLLAMA_CLOUD_API_KEY'),
            'model' => env('OLLAMA_CLOUD_MODEL', 'glm-5.1'),
        ],

        // Google Gemini API
        'gemini' => [
            'api_key' => env('GEMINI_API_KEY'),
            'model' => env('GEMINI_MODEL', 'gemini-1.5-flash'),
        ],
    ],
    
    // Spam Detection Configuration
    'spam_detection' => [
        // Confidence threshold (0.0 - 1.0)
        // Emails with confidence >= this value will be marked as spam
        'confidence_threshold' => floatval(env('SPAM_THRESHOLD', '0.7')),
        
        // Analyze these email properties
        'analyze_fields' => [
            'headers' => true,      // Subject, From, Reply-To, etc.
            'body' => true,         // Email body content
            'attachments' => true,  // Attachment names and types
            'urls' => true,         // URLs in email content
            'sender_reputation' => false, // Optional: check sender IP/domain
        ],
        
        // Maximum email size to analyze (in bytes)
        'max_email_size' => intval(env('MAX_EMAIL_SIZE', 10485760)), // 10MB
        
        // Timeout for AI API requests (seconds)
        'api_timeout' => intval(env('API_TIMEOUT', 30)),
    ],
    
    // Queue Processing
    'queue' => [
        // Queue storage directory
        'queue_dir' => env('QUEUE_DIR', "{$installDir}/queue"),
        
        // Maximum concurrent AI requests
        'max_concurrent' => intval(env('MAX_CONCURRENT_REQUESTS', 5)),
        
        // Retry failed emails N times
        'max_retries' => intval(env('MAX_RETRIES', 3)),
        
        // Retry delay in seconds
        'retry_delay' => intval(env('RETRY_DELAY', 300)),
    ],
    
    // QMAIL Integration
    'qmail' => [
        // QMAIL mailbox root (typically /home/mail)
        'mailbox_root' => env('QMAIL_MAILBOX_ROOT', '/home/mail'),
        
        // Create .Spam folder if it doesn't exist
        'create_spam_folder' => env('CREATE_SPAM_FOLDER', true),
        
        // Also mark email as Seen/Read when moved to Spam
        'mark_as_seen' => env('MARK_AS_SEEN', false),
        
        // Preserve original email in Inbox (copy instead of move)
        'preserve_original' => env('PRESERVE_ORIGINAL', false),
    ],
    
    // Stats
    'stats' => [
        // JSONL file for SysAdminHCP dashboard statistics
        'stats_file' => env('STATS_FILE', "{$installDir}/stats/stats.jsonl"),
        // JSONL file for AI token usage tracking
        'token_usage_file' => env('TOKEN_USAGE_FILE', "{$installDir}/stats/token-usage.jsonl"),
    ],

    // Logging
    'logging' => [
        // Log directory
        'log_dir' => env('LOG_DIR', "{$installDir}/logs"),
        
        // Log level: 'debug', 'info', 'warning', 'error'
        'level' => env('LOG_LEVEL', 'info'),
        
        // Maximum log file size (bytes) before rotation
        'max_size' => intval(env('LOG_MAX_SIZE', 10485760)), // 10MB
        
        // Keep N rotated log files
        'keep_files' => intval(env('KEEP_LOG_FILES', 10)),
    ],
    
    // Testing & Development
    'development' => [
        // Enable debug mode (verbose logging)
        'debug' => env('DEBUG', false),
        
        // Dry-run mode (analyze but don't move emails)
        'dry_run' => env('DRY_RUN', false),
        
        // Test mode (use mock AI responses)
        'test_mode' => env('TEST_MODE', false),
    ],
];

/**
 * Load .env file into environment variables
 */
function loadEnvFile(): void
{
    // Try multiple possible .env file locations
    $possiblePaths = [
        __DIR__ . '/../.env',                    // Default location
        __DIR__ . '/.env',                       // In config directory
        getcwd() . '/.env',                      // Current working directory
        getenv('INSTALL_DIR') . '/.env',         // Install directory
    ];
    
    // Also check /home/{user}/qmail-ai-filter/.env pattern
    if ($user = getenv('INSTALL_USER') ?: 'admin') {
        $possiblePaths[] = "/home/{$user}/qmail-ai-filter/.env";
    }
    
    foreach ($possiblePaths as $envFile) {
        if (file_exists($envFile)) {
            parseEnvFile($envFile);
            return; // Stop after first found
        }
    }
}

/**
 * Parse .env file and set environment variables
 */
function parseEnvFile(string $filePath): void
{
    if (!is_readable($filePath)) {
        return;
    }
    
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    
    foreach ($lines as $line) {
        // Skip comments
        if (strpos(trim($line), '#') === 0) {
            continue;
        }
        
        // Skip lines without =
        if (strpos($line, '=') === false) {
            continue;
        }
        
        // Parse KEY=VALUE
        [$key, $value] = explode('=', $line, 2);
        $key = trim($key);
        $value = trim($value);
        
        // Remove quotes if present
        if (preg_match('/^["\'](.+)["\']$/', $value, $matches)) {
            $value = $matches[1];
        }
        
        // Only set if not already set (environment variables take precedence)
        if (getenv($key) === false) {
            putenv("{$key}={$value}");
            $_ENV[$key] = $value;
        }
    }
}

/**
 * Get environment variable with optional default value
 */
function env($key, $default = null)
{
    // First check $_ENV (from putenv)
    if (isset($_ENV[$key])) {
        return $_ENV[$key];
    }
    
    // Then check getenv
    $value = getenv($key);
    return $value !== false ? $value : $default;
}

