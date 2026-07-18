<?php
/**
 * QMAIL AI Filter - Spam Filter Engine
 * 
 * Main filtering logic with AI-powered spam detection
 * 
 * @package    QmailAiFilter\Filter
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

namespace QmailAiFilter\Filter;

use QmailAiFilter\AI\AIProviderInterface;
use QmailAiFilter\Email\EmailParser;
use QmailAiFilter\Email\MailboxManager;
use QmailAiFilter\Logging\Logger;

class SpamFilterEngine
{
    private $aiProvider;
    private $mailboxManager;
    private $logger;
    private $confidenceThreshold;
    private $dryRun;
    private $preserveOriginal;
    
    public function __construct(
        AIProviderInterface $aiProvider,
        MailboxManager $mailboxManager,
        Logger $logger,
        float $confidenceThreshold = 0.7,
        bool $dryRun = false,
        bool $preserveOriginal = false
    ) {
        $this->aiProvider = $aiProvider;
        $this->mailboxManager = $mailboxManager;
        $this->logger = $logger;
        $this->confidenceThreshold = $confidenceThreshold;
        $this->dryRun = $dryRun;
        $this->preserveOriginal = $preserveOriginal;
    }
    
    /**
     * Process email and determine if it's spam
     * 
     * @param string $emailPath Path to email file
     * @param string $userDomain User@domain of recipient
     * @return array Analysis result
     */
    public function processEmail(string $emailPath, string $userDomain): array
    {
        $this->logger->info("Processing email", ['file' => $emailPath, 'user' => $userDomain]);
        
        try {
            // Parse email
            $parser = new EmailParser($emailPath);
            $emailData = $parser->getEmailData();
            
            // Analyze with AI
            $analysis = $this->aiProvider->analyzeEmail($emailData);
            
            // Log result
            $this->logger->info("Spam analysis complete", [
                'user' => $userDomain,
                'is_spam' => $analysis['is_spam'],
                'confidence' => $analysis['confidence'],
                'reason' => $analysis['reason'] ?? '',
            ]);
            
            // Check threshold and move if needed
            $result = [
                'processed' => true,
                'email_file' => $emailPath,
                'user' => $userDomain,
                'is_spam' => $analysis['is_spam'],
                'confidence' => $analysis['confidence'],
                'reason' => $analysis['reason'] ?? 'Unknown',
                'spam_type' => $analysis['spam_type'] ?? 'unknown',
                'moved_to_spam' => false,
            ];
            
            if ($analysis['is_spam'] && $analysis['confidence'] >= $this->confidenceThreshold) {
                $result['moved_to_spam'] = $this->mailboxManager->moveToSpam(
                    $userDomain,
                    $emailPath,
                    $this->preserveOriginal
                );
                
                if ($result['moved_to_spam']) {
                    $this->logger->warning("Email moved to Spam", [
                        'user' => $userDomain,
                        'confidence' => $analysis['confidence'],
                    ]);
                }
            }
            
            return $result;
        } catch (\Exception $e) {
            $this->logger->error("Error processing email: " . $e->getMessage(), [
                'file' => $emailPath,
                'user' => $userDomain,
            ]);
            
            return [
                'processed' => false,
                'email_file' => $emailPath,
                'user' => $userDomain,
                'error' => $e->getMessage(),
            ];
        }
    }
    
    /**
     * Process multiple emails
     */
    public function processEmailBatch(array $emails): array
    {
        $results = [];
        
        foreach ($emails as $email) {
            $emailPath = $email['path'] ?? '';
            $userDomain = $email['user'] ?? '';
            
            if (empty($emailPath) || empty($userDomain)) {
                continue;
            }
            
            $results[] = $this->processEmail($emailPath, $userDomain);
        }
        
        return $results;
    }
    
    /**
     * Set confidence threshold
     */
    public function setConfidenceThreshold(float $threshold): void
    {
        $this->confidenceThreshold = max(0, min(1, $threshold));
    }
    
    /**
     * Get confidence threshold
     */
    public function getConfidenceThreshold(): float
    {
        return $this->confidenceThreshold;
    }
    
    /**
     * Get AI provider info
     */
    public function getProviderInfo(): array
    {
        return [
            'provider' => $this->aiProvider->getProviderName(),
            'configured' => $this->aiProvider->isConfigured(),
            'threshold' => $this->confidenceThreshold,
            'dry_run' => $this->dryRun,
        ];
    }
}
