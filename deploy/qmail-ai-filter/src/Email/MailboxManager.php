<?php
/**
 * QMAIL AI Filter - Mailbox Manager
 * 
 * Handles email folder operations and Maildir++ management
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

use QmailAiFilter\Logging\Logger;

class MailboxManager
{
    private $mailboxRoot;
    private $logger;
    private $dryRun;
    
    public function __construct(string $mailboxRoot = '/home/mail', Logger $logger = null, bool $dryRun = false)
    {
        $this->mailboxRoot = rtrim($mailboxRoot, '/');
        $this->logger = $logger ?? new Logger();
        $this->dryRun = $dryRun;
    }
    
    /**
     * Move email to Spam folder
     * 
     * @param string $userDomain User/domain identifier (e.g., "user@domain.com")
     * @param string $emailPath Path to email file
     * @param bool $preserveOriginal Keep copy in inbox
     * @return bool Success status
     */
    public function moveToSpam(string $userDomain, string $emailPath, bool $preserveOriginal = false): bool
    {
        try {
            // Parse user@domain
            if (strpos($userDomain, '@') === false) {
                $this->logger->error("Invalid user@domain format: {$userDomain}");
                return false;
            }
            
            [$user, $domain] = explode('@', $userDomain, 2);
            $user = strtolower(trim($user));
            $domain = strtolower(trim($domain));
            
            // Construct paths
            $mailDir = "{$this->mailboxRoot}/{$domain}/{$user}";
            $spamDir = "{$mailDir}/.Spam";
            
            if (!$this->dryRun) {
                // Create .Spam folder if needed
                if (!is_dir($spamDir)) {
                    if (!$this->createSpamFolder($spamDir)) {
                        return false;
                    }
                }
                
                // Move or copy email
                $filename = basename($emailPath);
                $targetPath = "{$spamDir}/new/{$filename}";
                
                if ($preserveOriginal) {
                    if (!copy($emailPath, $targetPath)) {
                        $this->logger->error("Failed to copy email to Spam: {$emailPath} -> {$targetPath}");
                        return false;
                    }
                    $this->logger->info("Email copied to Spam", ['user' => $userDomain, 'file' => $filename]);
                } else {
                    if (!rename($emailPath, $targetPath)) {
                        $this->logger->error("Failed to move email to Spam: {$emailPath} -> {$targetPath}");
                        return false;
                    }
                    $this->logger->info("Email moved to Spam", ['user' => $userDomain, 'file' => $filename]);
                }
                
                // Set proper permissions
                @chmod($targetPath, 0600);
                @chmod(dirname($targetPath), 0700);
            } else {
                $this->logger->info("DRY RUN: Would move email to Spam", ['user' => $userDomain]);
            }
            
            return true;
        } catch (\Exception $e) {
            $this->logger->error("Error moving email to Spam: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Create .Spam folder with proper structure
     */
    private function createSpamFolder(string $spamDir): bool
    {
        try {
            $subdirs = ['new', 'cur', 'tmp'];
            
            foreach ($subdirs as $subdir) {
                $path = "{$spamDir}/{$subdir}";
                if (!is_dir($path)) {
                    if (!@mkdir($path, 0700, true)) {
                        $this->logger->error("Failed to create spam directory: {$path}");
                        return false;
                    }
                }
            }
            
            // Create maildirplus files
            $this->createMaildirFile("{$spamDir}/maildirfolder");
            $this->createMaildirFile("{$spamDir}/maildirplus");
            
            $this->logger->info("Created .Spam folder structure: {$spamDir}");
            return true;
        } catch (\Exception $e) {
            $this->logger->error("Error creating Spam folder: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Create maildir marker file
     */
    private function createMaildirFile(string $filepath): void
    {
        if (!file_exists($filepath)) {
            @touch($filepath);
            @chmod($filepath, 0600);
        }
    }
    
    /**
     * Get user's email folders
     */
    public function getUserFolders(string $userDomain): array
    {
        try {
            if (strpos($userDomain, '@') === false) {
                return [];
            }
            
            [$user, $domain] = explode('@', $userDomain, 2);
            $mailDir = "{$this->mailboxRoot}/{$domain}/{$user}";
            
            if (!is_dir($mailDir)) {
                return [];
            }
            
            $folders = [];
            $items = scandir($mailDir);
            
            foreach ($items as $item) {
                if ($item[0] === '.' && $item !== '.' && $item !== '..') {
                    $folders[] = $item;
                }
            }
            
            return $folders;
        } catch (\Exception $e) {
            $this->logger->error("Error getting user folders: " . $e->getMessage());
            return [];
        }
    }
    
    /**
     * Check if Spam folder exists
     */
    public function hasSpamFolder(string $userDomain): bool
    {
        try {
            if (strpos($userDomain, '@') === false) {
                return false;
            }
            
            [$user, $domain] = explode('@', $userDomain, 2);
            $spamDir = "{$this->mailboxRoot}/{$domain}/{$user}/.Spam";
            
            return is_dir($spamDir);
        } catch (\Exception $e) {
            return false;
        }
    }
}
