<?php
/**
 * QMAIL AI Filter - AI Provider Interface
 * 
 * Defines the contract for all AI providers used in spam detection
 * 
 * @package    QmailAiFilter\AI
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

namespace QmailAiFilter\AI;

interface AIProviderInterface
{
    /**
     * Analyze email content for spam
     * 
     * @param array $emailData Email content and metadata
     * @return array ['is_spam' => bool, 'confidence' => float, 'reason' => string]
     */
    public function analyzeEmail(array $emailData): array;
    
    /**
     * Check if the provider is properly configured
     * 
     * @return bool
     */
    public function isConfigured(): bool;
    
    /**
     * Get provider name
     * 
     * @return string
     */
    public function getProviderName(): string;
}
