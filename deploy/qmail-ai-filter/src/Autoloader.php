<?php
/**
 * QMAIL AI Filter - PSR-4 Autoloader
 * 
 * @package    QmailAiFilter
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

class Autoloader
{
    private static $prefixes = [];
    
    public static function register(): void
    {
        spl_autoload_register([self::class, 'autoload']);
        
        // Register QmailAiFilter namespace
        self::addPrefix('QmailAiFilter', __DIR__);
    }
    
    public static function addPrefix(string $prefix, string $path): void
    {
        self::$prefixes[$prefix] = rtrim($path, '/');
    }
    
    public static function autoload(string $class): void
    {
        foreach (self::$prefixes as $prefix => $path) {
            if (strpos($class, $prefix) === 0) {
                $relative = substr($class, strlen($prefix));
                $file = $path . str_replace('\\', '/', $relative) . '.php';
                
                if (file_exists($file)) {
                    require $file;
                    return;
                }
            }
        }
    }
}
