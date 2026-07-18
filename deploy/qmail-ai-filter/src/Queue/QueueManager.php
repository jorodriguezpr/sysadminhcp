<?php
/**
 * QMAIL AI Filter - Queue Manager
 * 
 * Handles asynchronous email processing with JSON-based queue
 * 
 * @package    QmailAiFilter\Queue
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

namespace QmailAiFilter\Queue;

use QmailAiFilter\Logging\Logger;

class QueueManager
{
    private $queueDir;
    private $logger;
    private $maxRetries;
    private $retryDelay;
    
    public function __construct(string $queueDir = null, Logger $logger = null, int $maxRetries = 3, int $retryDelay = 300)
    {
        $this->queueDir = $queueDir ?? __DIR__ . '/../../queue';
        $this->logger = $logger ?? new Logger();
        $this->maxRetries = $maxRetries;
        $this->retryDelay = $retryDelay;
        
        $this->ensureQueueDirs();
    }
    
    /**
     * Ensure queue directories exist
     */
    private function ensureQueueDirs(): void
    {
        $dirs = ['pending', 'processing', 'completed', 'failed'];
        
        foreach ($dirs as $dir) {
            $path = "{$this->queueDir}/{$dir}";
            if (!is_dir($path)) {
                @mkdir($path, 0755, true);
            }
        }
    }
    
    /**
     * Add email to processing queue
     */
    public function enqueue(string $emailPath, string $userDomain, array $metadata = []): bool
    {
        try {
            $queueId = uniqid('email_', true);
            
            $queueItem = [
                'id' => $queueId,
                'email_path' => $emailPath,
                'user_domain' => $userDomain,
                'created_at' => time(),
                'retry_count' => 0,
                'metadata' => $metadata,
            ];
            
            $queueFile = "{$this->queueDir}/pending/{$queueId}.json";
            
            if (file_put_contents($queueFile, json_encode($queueItem, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES))) {
                chmod($queueFile, 0644);
                $this->logger->info("Email queued for processing", ['id' => $queueId, 'user' => $userDomain]);
                return true;
            }
            
            $this->logger->error("Failed to write queue file: {$queueFile}");
            return false;
        } catch (\Exception $e) {
            $this->logger->error("Error enqueuing email: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Get pending emails from queue
     */
    public function getPending(int $limit = 10): array
    {
        $pending = [];
        $pendingDir = "{$this->queueDir}/pending";
        
        if (!is_dir($pendingDir)) {
            return [];
        }
        
        $files = array_slice(scandir($pendingDir), 2); // Skip . and ..
        $count = 0;
        
        foreach ($files as $file) {
            if (!preg_match('/\.json$/', $file)) {
                continue;
            }
            
            $filePath = "{$pendingDir}/{$file}";
            $content = file_get_contents($filePath);
            $item = json_decode($content, true);
            
            if ($item) {
                $pending[] = [
                    'file' => $filePath,
                    'data' => $item,
                ];
                $count++;
            }
            
            if ($count >= $limit) {
                break;
            }
        }
        
        return $pending;
    }
    
    /**
     * Mark email as being processed
     */
    public function markProcessing(string $queueId): bool
    {
        return $this->moveQueueFile($queueId, 'pending', 'processing');
    }
    
    /**
     * Mark email as completed
     */
    public function markCompleted(string $queueId, array $result = []): bool
    {
        try {
            $processingFile = "{$this->queueDir}/processing/{$queueId}.json";
            
            if (file_exists($processingFile)) {
                $item = json_decode(file_get_contents($processingFile), true);
                $item['completed_at'] = time();
                $item['result'] = $result;
                
                $completedFile = "{$this->queueDir}/completed/{$queueId}.json";
                file_put_contents($completedFile, json_encode($item, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
                unlink($processingFile);
                
                $this->logger->info("Queue item completed", ['id' => $queueId]);
                return true;
            }
            
            return false;
        } catch (\Exception $e) {
            $this->logger->error("Error marking completed: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Mark email as failed
     */
    public function markFailed(string $queueId, string $error = ''): bool
    {
        try {
            $processingFile = "{$this->queueDir}/processing/{$queueId}.json";
            
            if (file_exists($processingFile)) {
                $item = json_decode(file_get_contents($processingFile), true);
                $item['retry_count'] = ($item['retry_count'] ?? 0) + 1;
                $item['last_error'] = $error;
                $item['failed_at'] = time();
                
                if ($item['retry_count'] >= $this->maxRetries) {
                    $failedFile = "{$this->queueDir}/failed/{$queueId}.json";
                    file_put_contents($failedFile, json_encode($item, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
                    unlink($processingFile);
                    
                    $this->logger->error("Queue item permanently failed", ['id' => $queueId, 'error' => $error]);
                } else {
                    // Requeue for retry
                    $nextRetry = time() + ($this->retryDelay * $item['retry_count']);
                    $item['next_retry'] = $nextRetry;
                    
                    $pendingFile = "{$this->queueDir}/pending/{$queueId}.json";
                    file_put_contents($pendingFile, json_encode($item, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
                    unlink($processingFile);
                    
                    $this->logger->warning("Queue item requeued for retry", ['id' => $queueId, 'retry' => $item['retry_count']]);
                }
                
                return true;
            }
            
            return false;
        } catch (\Exception $e) {
            $this->logger->error("Error marking failed: " . $e->getMessage());
            return false;
        }
    }
    
    /**
     * Move queue file between directories
     */
    private function moveQueueFile(string $queueId, string $fromDir, string $toDir): bool
    {
        $fromFile = "{$this->queueDir}/{$fromDir}/{$queueId}.json";
        $toFile = "{$this->queueDir}/{$toDir}/{$queueId}.json";
        
        if (file_exists($fromFile)) {
            return rename($fromFile, $toFile);
        }
        
        return false;
    }
    
    /**
     * Get queue statistics
     */
    public function getStats(): array
    {
        return [
            'pending' => $this->countFiles("{$this->queueDir}/pending"),
            'processing' => $this->countFiles("{$this->queueDir}/processing"),
            'completed' => $this->countFiles("{$this->queueDir}/completed"),
            'failed' => $this->countFiles("{$this->queueDir}/failed"),
        ];
    }
    
    /**
     * Count JSON files in directory
     */
    private function countFiles(string $dir): int
    {
        if (!is_dir($dir)) {
            return 0;
        }
        
        return count(array_filter(scandir($dir), function ($f) {
            return preg_match('/\.json$/', $f);
        }));
    }
    
    /**
     * Clean old completed/failed items
     */
    public function cleanup(int $ageSeconds = 604800): void // 7 days default
    {
        try {
            $cutoffTime = time() - $ageSeconds;
            $dirs = ['completed', 'failed'];
            
            foreach ($dirs as $dir) {
                $dirPath = "{$this->queueDir}/{$dir}";
                if (!is_dir($dirPath)) {
                    continue;
                }
                
                $files = scandir($dirPath);
                foreach ($files as $file) {
                    if (!preg_match('/\.json$/', $file)) {
                        continue;
                    }
                    
                    $filePath = "{$dirPath}/{$file}";
                    if (filemtime($filePath) < $cutoffTime) {
                        unlink($filePath);
                    }
                }
            }
            
            $this->logger->info("Queue cleanup completed");
        } catch (\Exception $e) {
            $this->logger->error("Error during queue cleanup: " . $e->getMessage());
        }
    }
}
