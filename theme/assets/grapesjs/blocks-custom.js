/**
 * SysAdminHCP Page Builder — custom GrapesJS block library.
 * Registered as a plugin ('sysadminhcp-blocks') so it can sit alongside grapesjs-preset-webpage
 * in the `plugins:[...]` list passed to grapesjs.init() without needing a bundler — loaded as a
 * plain <script> after grapes.min.js, same pattern as preset-webpage.min.js.
 */
(function () {
  if (typeof grapesjs === 'undefined') return;

  grapesjs.plugins.add('sysadminhcp-blocks', (editor) => {
    const bm = editor.BlockManager;

    // ── Layout ──
    bm.add('navbar', {
      label: '🔀 Navigation Bar',
      category: 'Layout',
      content: `<nav data-gjs-type="navbar" style="display:flex;justify-content:space-between;align-items:center;padding:15px 30px;background:#fff;box-shadow:0 2px 4px rgba(0,0,0,0.1);">
        <a href="/" style="font-size:1.5rem;font-weight:bold;text-decoration:none;color:#333;">Logo</a>
        <div style="display:flex;gap:25px;">
          <a href="/" style="text-decoration:none;color:#555;">Home</a>
          <a href="/about.html" style="text-decoration:none;color:#555;">About</a>
          <a href="/services.html" style="text-decoration:none;color:#555;">Services</a>
          <a href="/contact.html" style="text-decoration:none;color:#555;">Contact</a>
        </div>
      </nav>`,
    });

    bm.add('hero-section', {
      label: '🏆 Hero Section',
      category: 'Layout',
      content: `<section style="text-align:center;padding:80px 20px;background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;">
        <h1 style="font-size:2.5rem;margin-bottom:15px;">Welcome to Our Website</h1>
        <p style="font-size:1.2rem;opacity:0.9;margin-bottom:25px;">Your compelling tagline goes here.</p>
        <a href="#" style="display:inline-block;padding:14px 35px;background:#fff;color:#667eea;text-decoration:none;border-radius:30px;font-weight:bold;">Get Started</a>
      </section>`,
    });

    bm.add('footer-dark', {
      label: '🦶 Dark Footer',
      category: 'Layout',
      content: `<footer style="background:#1a1a2e;color:#fff;padding:40px 20px 20px;margin-top:40px;">
        <div style="max-width:1200px;margin:0 auto;display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:30px;">
          <div><h3 style="color:#fff;">Company</h3><p style="color:#aaa;">Your company description goes here.</p></div>
          <div><h4 style="color:#fff;">Links</h4>
            <a href="/" style="display:block;color:#aaa;text-decoration:none;padding:3px 0;">Home</a>
            <a href="/about.html" style="display:block;color:#aaa;text-decoration:none;padding:3px 0;">About</a>
            <a href="/contact.html" style="display:block;color:#aaa;text-decoration:none;padding:3px 0;">Contact</a>
          </div>
          <div><h4 style="color:#fff;">Contact</h4><p style="color:#aaa;">contact@example.com</p><p style="color:#aaa;">+1 234 567 890</p></div>
        </div>
        <hr style="border:0;border-top:1px solid #333;margin:30px 0;">
        <p style="text-align:center;color:#666;">&copy; 2026 Your Company. All rights reserved.</p>
      </footer>`,
    });

    // ── Business ──
    bm.add('features-grid', {
      label: '📋 Features Grid',
      category: 'Business',
      content: `<section style="padding:60px 20px;max-width:1200px;margin:0 auto;">
        <h2 style="text-align:center;margin-bottom:40px;">Our Features</h2>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:30px;">
          <div style="text-align:center;padding:30px;border-radius:10px;background:#f8f9fa;"><div style="font-size:2rem;margin-bottom:10px;">⚡</div><h3>Fast</h3><p>Lightning-fast performance</p></div>
          <div style="text-align:center;padding:30px;border-radius:10px;background:#f8f9fa;"><div style="font-size:2rem;margin-bottom:10px;">🔒</div><h3>Secure</h3><p>Bank-grade security</p></div>
          <div style="text-align:center;padding:30px;border-radius:10px;background:#f8f9fa;"><div style="font-size:2rem;margin-bottom:10px;">📱</div><h3>Responsive</h3><p>Works on all devices</p></div>
        </div>
      </section>`,
    });

    bm.add('pricing-table', {
      label: '📊 Pricing Table',
      category: 'Business',
      content: `<section style="padding:60px 20px;max-width:1000px;margin:0 auto;">
        <h2 style="text-align:center;margin-bottom:40px;">Pricing Plans</h2>
        <div style="display:flex;flex-wrap:wrap;justify-content:center;gap:20px;">
          <div style="flex:1;min-width:250px;border:1px solid #ddd;border-radius:12px;padding:30px;text-align:center;">
            <h3>Basic</h3><p style="font-size:2.5rem;font-weight:bold;">$9<span style="font-size:1rem;">/mo</span></p>
            <ul style="list-style:none;padding:0;line-height:2;"><li>✓ 5 Pages</li><li>✓ 1GB Storage</li><li>✓ Email Support</li></ul>
            <button style="width:100%;padding:12px;background:#007bff;color:#fff;border:none;border-radius:8px;cursor:pointer;">Choose Plan</button>
          </div>
          <div style="flex:1;min-width:250px;border:2px solid #007bff;border-radius:12px;padding:30px;text-align:center;transform:scale(1.05);">
            <div style="background:#007bff;color:#fff;padding:5px 15px;border-radius:20px;display:inline-block;font-size:0.8rem;margin-bottom:10px;">POPULAR</div>
            <h3>Pro</h3><p style="font-size:2.5rem;font-weight:bold;">$29<span style="font-size:1rem;">/mo</span></p>
            <ul style="list-style:none;padding:0;line-height:2;"><li>✓ Unlimited Pages</li><li>✓ 50GB Storage</li><li>✓ Priority Support</li></ul>
            <button style="width:100%;padding:12px;background:#007bff;color:#fff;border:none;border-radius:8px;cursor:pointer;">Choose Plan</button>
          </div>
          <div style="flex:1;min-width:250px;border:1px solid #ddd;border-radius:12px;padding:30px;text-align:center;">
            <h3>Enterprise</h3><p style="font-size:2.5rem;font-weight:bold;">$99<span style="font-size:1rem;">/mo</span></p>
            <ul style="list-style:none;padding:0;line-height:2;"><li>✓ Everything in Pro</li><li>✓ Unlimited Storage</li><li>✓ 24/7 Support</li></ul>
            <button style="width:100%;padding:12px;background:#28a745;color:#fff;border:none;border-radius:8px;cursor:pointer;">Contact Us</button>
          </div>
        </div>
      </section>`,
    });

    bm.add('testimonial', {
      label: '💬 Testimonial',
      category: 'Business',
      content: `<section style="padding:60px 20px;background:#f8f9fa;">
        <blockquote style="max-width:700px;margin:0 auto;text-align:center;font-size:1.3rem;color:#555;font-style:italic;">
          "This is the best service I've ever used. Highly recommended!"
          <footer style="margin-top:15px;font-size:1rem;color:#888;">— Jane Doe, CEO of Example Inc.</footer>
        </blockquote>
      </section>`,
    });

    bm.add('cta-banner', {
      label: '📢 Call to Action',
      category: 'Business',
      content: `<section style="padding:50px 20px;background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;text-align:center;">
        <h2 style="font-size:2rem;margin-bottom:15px;">Ready to Get Started?</h2>
        <p style="font-size:1.1rem;opacity:0.9;margin-bottom:25px;">Join thousands of satisfied customers today.</p>
        <a href="#" style="display:inline-block;padding:14px 40px;background:#fff;color:#667eea;text-decoration:none;border-radius:30px;font-weight:bold;">Sign Up Now</a>
      </section>`,
    });

    // ── Interactive ──
    bm.add('faq-accordion', {
      label: '❓ FAQ Accordion',
      category: 'Interactive',
      content: `<section style="padding:60px 20px;max-width:800px;margin:0 auto;">
        <h2 style="text-align:center;margin-bottom:30px;">Frequently Asked Questions</h2>
        <div style="border-radius:8px;overflow:hidden;border:1px solid #ddd;">
          <details style="border-bottom:1px solid #ddd;padding:15px 20px;"><summary style="font-weight:bold;cursor:pointer;">What is included in the free plan?</summary><p style="margin-top:10px;color:#666;">All core hosting features including domains, mail, DNS, and SSL.</p></details>
          <details style="border-bottom:1px solid #ddd;padding:15px 20px;"><summary style="font-weight:bold;cursor:pointer;">Can I upgrade later?</summary><p style="margin-top:10px;color:#666;">Yes, you can upgrade to Pro at any time.</p></details>
          <details style="padding:15px 20px;"><summary style="font-weight:bold;cursor:pointer;">Do you offer support?</summary><p style="margin-top:10px;color:#666;">Pro plans include ticket support.</p></details>
        </div>
      </section>`,
    });

    bm.add('contact-form-handler', {
      label: '📧 Contact Form (with handler)',
      category: 'Interactive',
      content: `<form action="/api/site-builder-form/submit" method="POST" style="max-width:500px;margin:0 auto;padding:40px 20px;">
        <input type="hidden" name="_domain" value="__SB_DOMAIN__">
        <div style="position:absolute;left:-9999px;" aria-hidden="true"><label>Leave this field empty</label><input type="text" name="_hp" tabindex="-1" autocomplete="off"></div>
        <div style="margin-bottom:15px;"><label style="display:block;margin-bottom:5px;font-weight:bold;">Name</label><input type="text" name="name" required style="width:100%;padding:10px;border:1px solid #ccc;border-radius:6px;"></div>
        <div style="margin-bottom:15px;"><label style="display:block;margin-bottom:5px;font-weight:bold;">Email</label><input type="email" name="email" required style="width:100%;padding:10px;border:1px solid #ccc;border-radius:6px;"></div>
        <div style="margin-bottom:15px;"><label style="display:block;margin-bottom:5px;font-weight:bold;">Message</label><textarea name="message" rows="5" required style="width:100%;padding:10px;border:1px solid #ccc;border-radius:6px;"></textarea></div>
        <button type="submit" style="width:100%;padding:12px;background:#007bff;color:#fff;border:none;border-radius:8px;font-size:1rem;cursor:pointer;">Send Message</button>
      </form>`,
    });

    // ── Social ──
    bm.add('social-bar', {
      label: '📱 Social Media Bar',
      category: 'Social',
      content: `<div style="text-align:center;padding:20px;">
        <a href="#" style="display:inline-block;margin:0 10px;width:40px;height:40px;line-height:40px;border-radius:50%;background:#1877F2;color:#fff;text-decoration:none;font-size:1.2rem;">f</a>
        <a href="#" style="display:inline-block;margin:0 10px;width:40px;height:40px;line-height:40px;border-radius:50%;background:#1DA1F2;color:#fff;text-decoration:none;font-size:1.2rem;">t</a>
        <a href="#" style="display:inline-block;margin:0 10px;width:40px;height:40px;line-height:40px;border-radius:50%;background:#E4405F;color:#fff;text-decoration:none;font-size:1.2rem;">ig</a>
        <a href="#" style="display:inline-block;margin:0 10px;width:40px;height:40px;line-height:40px;border-radius:50%;background:#0A66C2;color:#fff;text-decoration:none;font-size:1.2rem;">in</a>
        <a href="#" style="display:inline-block;margin:0 10px;width:40px;height:40px;line-height:40px;border-radius:50%;background:#FF0000;color:#fff;text-decoration:none;font-size:1.2rem;">yt</a>
      </div>`,
    });

    // ── Media ──
    bm.add('gallery-grid', {
      label: '🖼 Image Gallery',
      category: 'Media',
      content: `<section style="padding:40px 20px;max-width:1200px;margin:0 auto;">
        <h2 style="text-align:center;margin-bottom:30px;">Gallery</h2>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:15px;">
          <img src="https://via.placeholder.com/300x200" style="width:100%;border-radius:8px;" alt="Gallery image">
          <img src="https://via.placeholder.com/300x200" style="width:100%;border-radius:8px;" alt="Gallery image">
          <img src="https://via.placeholder.com/300x200" style="width:100%;border-radius:8px;" alt="Gallery image">
          <img src="https://via.placeholder.com/300x200" style="width:100%;border-radius:8px;" alt="Gallery image">
        </div>
      </section>`,
    });

    bm.add('video-embed', {
      label: '🎥 Video Embed',
      category: 'Media',
      content: `<section style="padding:40px 20px;max-width:800px;margin:0 auto;">
        <div style="position:relative;padding-bottom:56.25%;height:0;overflow:hidden;border-radius:12px;">
          <iframe src="about:blank" data-placeholder-video="1" style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;" allowfullscreen title="Video"></iframe>
        </div>
      </section>`,
    });
  });
})();
