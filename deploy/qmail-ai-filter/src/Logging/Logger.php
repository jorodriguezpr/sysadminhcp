<?php
/**
 * QMAIL AI Filter - Logger
 * 
 * Handles all logging operations with rotation and structured output
 * 
 * @package    QmailAiFilter\Logging
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

namespace QmailAiFilter\Logging;

class Logger
{
    private $logDir;
    private $level;
    private $levels = ['debug' => 0, 'info' => 1, 'warning' => 2, 'error' => 3];
    
    public function __construct(string $logDir = null, string $level = 'info')
    {
        $this->logDir = $logDir ?? __DIR__ . '/../../logs';
        $this->level = $level;
        
        if (!is_dir($this->logDir)) {
            @mkdir($this->logDir, 0755, true);
        }
    }
    
    public function debug(string $message, array $context = []): void
    {
        $this->log('debug', $message, $context);
    }
    
    public function info(string $message, array $context = []): void
    {
        $this->log('info', $message, $context);
    }
    
    public function warning(string $message, array $context = []): void
    {
        $this->log('warning', $message, $context);
    }
    
    public function error(string $message, array $context = []): void
    {
        $this->log('error', $message, $context);
    }
    
    private function log(string $level, string $message, array $context = []): void
    {
        if (($this->levels[$level] ?? 1) < ($this->levels[$this->level] ?? 1)) {
            return;
        }
        
        $timestamp = date('Y-m-d H:i:s');
        $contextStr = !empty($context) ? ' ' . json_encode($context) : '';
        $logMessage = "[{$timestamp}] [{$level}] {$message}{$contextStr}\n";
        
        $logFile = $this->logDir . '/qmail-ai-filter.log';
        @file_put_contents($logFile, $logMessage, FILE_APPEND | LOCK_EX);
        
        // Rotate log file if it gets too large
        if (filesize($logFile) > 10485760) { // 10MB
            $this->rotateLog($logFile);
        }
    }
    
    private function rotateLog(string $logFile): void
    {
        $timestamp = date('Y-m-d_H-i-s');
        $backupFile = $logFile . '.' . $timestamp;
        rename($logFile, $backupFile);
        
        // Clean old log files
        $logDir = dirname($logFile);
        $files = glob($logDir . '/qmail-ai-filter.log.*');
        usort($files, function ($a, $b) {
            return filemtime($a) - filemtime($b);
        });
        
        while (count($files) > 10) {
            unlink(array_shift($files));
        }
    }
}
