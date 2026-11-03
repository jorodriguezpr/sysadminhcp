/**
 * SysAdminHCP Site Builder — section library (S2).
 *
 * Every section is styled only through the site's design tokens (/sb-site.css, Page Builder →
 * 🎨 Design): `sb-*` classes, no inline colours or fonts, so a design change restyles them all.
 * Rules (enforced by tests/sitebuilder/sections.test.ts):
 *   - only classes that sb-site.css defines; no <script>, no event handlers, no external URLs;
 *   - no inline CSS shorthand containing var() (GrapesJS's parser drops those);
 *   - root element is <section data-sb-section="<id>">.
 * Used by blocks-custom.js (Blocks panel → "Sections") and the "➕ Section" picker in sitebuilder.js.
 */
(function (root) {
  // Neutral placeholder image (replace via double-click → Asset Manager). Inline SVG data URI, so
  // nothing is fetched from a third party.
  const IMG = (w, h, label) => `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='${w}' height='${h}' viewBox='0 0 ${w} ${h}'%3E%3Crect width='100%25' height='100%25' fill='%23cbd5e1'/%3E%3Ctext x='50%25' y='50%25' font-family='sans-serif' font-size='${Math.round(h / 12)}' fill='%2364748b' text-anchor='middle' dominant-baseline='middle'%3E${encodeURIComponent(label || 'Image')}%3C/text%3E%3C/svg%3E`;

  const card = (title, text, icon) => `<div class="sb-card">${icon ? `<div class="sb-icon">${icon}</div>` : ''}<h3 class="sb-heading sb-heading-sm">${title}</h3><p class="sb-text sb-muted">${text}</p></div>`;

  const SECTIONS = [
    {
      id: 'hero-center', group: 'Hero', label: 'Hero — centered',
      description: 'Big headline, short pitch and two buttons.',
      html: `<section class="sb-section sb-hero" data-sb-section="hero-center"><div class="sb-container sb-narrow sb-center">
  <p class="sb-eyebrow">Welcome</p>
  <h1 class="sb-heading sb-heading-xl">A clear headline that says what you do</h1>
  <p class="sb-lead">One or two sentences that explain who it is for and why it matters.</p>
  <div class="sb-actions"><a class="sb-btn" href="#">Get started</a><a class="sb-btn sb-btn-outline" href="#">Learn more</a></div>
</div></section>`,
    },
    {
      id: 'hero-split', group: 'Hero', label: 'Hero — text + image',
      description: 'Headline and buttons beside a large image.',
      html: `<section class="sb-section sb-hero" data-sb-section="hero-split"><div class="sb-container sb-split">
  <div>
    <p class="sb-eyebrow">New</p>
    <h1 class="sb-heading sb-heading-xl">Your product, explained in one line</h1>
    <p class="sb-lead">Describe the main benefit. Keep it short — visitors decide in seconds.</p>
    <div class="sb-actions sb-actions-start"><a class="sb-btn" href="#">Start now</a><a class="sb-btn sb-btn-outline" href="#">See how it works</a></div>
  </div>
  <img class="sb-media" src="${IMG(800, 600, 'Hero image')}" alt="">
</div></section>`,
    },
    {
      id: 'features-3', group: 'Features', label: 'Features — three cards',
      description: 'Three benefits with icons.',
      html: `<section class="sb-section" data-sb-section="features-3"><div class="sb-container">
  <div class="sb-center sb-narrow"><p class="sb-eyebrow">Why us</p><h2 class="sb-heading">Everything you need</h2><p class="sb-text sb-muted">A short introduction to what makes you different.</p></div>
  <div class="sb-grid">
    ${card('Fast', 'Explain the first benefit in a sentence or two.', '⚡')}
    ${card('Reliable', 'Explain the second benefit in a sentence or two.', '🛡️')}
    ${card('Friendly support', 'Explain the third benefit in a sentence or two.', '💬')}
  </div>
</div></section>`,
    },
    {
      id: 'features-6', group: 'Features', label: 'Features — six item grid',
      description: 'Six short points in a grid, no cards.',
      html: `<section class="sb-section sb-section-alt" data-sb-section="features-6"><div class="sb-container">
  <div class="sb-center sb-narrow"><h2 class="sb-heading">What's included</h2></div>
  <div class="sb-grid sb-grid-3">
    <div><div class="sb-icon">✅</div><h3 class="sb-heading sb-heading-sm">Feature one</h3><p class="sb-text sb-muted">Short description.</p></div>
    <div><div class="sb-icon">📈</div><h3 class="sb-heading sb-heading-sm">Feature two</h3><p class="sb-text sb-muted">Short description.</p></div>
    <div><div class="sb-icon">🔒</div><h3 class="sb-heading sb-heading-sm">Feature three</h3><p class="sb-text sb-muted">Short description.</p></div>
    <div><div class="sb-icon">📱</div><h3 class="sb-heading sb-heading-sm">Feature four</h3><p class="sb-text sb-muted">Short description.</p></div>
    <div><div class="sb-icon">🌍</div><h3 class="sb-heading sb-heading-sm">Feature five</h3><p class="sb-text sb-muted">Short description.</p></div>
    <div><div class="sb-icon">⏱️</div><h3 class="sb-heading sb-heading-sm">Feature six</h3><p class="sb-text sb-muted">Short description.</p></div>
  </div>
</div></section>`,
    },
    {
      id: 'media-text', group: 'Content', label: 'Image + text',
      description: 'An image beside a paragraph and a link.',
      html: `<section class="sb-section" data-sb-section="media-text"><div class="sb-container sb-split">
  <img class="sb-media" src="${IMG(800, 600)}" alt="">
  <div>
    <h2 class="sb-heading">Tell your story</h2>
    <p class="sb-text">Use this space to describe your company, a product or a service. Two short paragraphs read better than one long one.</p>
    <p class="sb-text sb-muted">Add a second paragraph with supporting detail.</p>
    <a class="sb-btn" href="#">Read more</a>
  </div>
</div></section>`,
    },
    {
      id: 'text-media', group: 'Content', label: 'Text + image',
      description: 'Same as Image + text, image on the right.',
      html: `<section class="sb-section sb-section-alt" data-sb-section="text-media"><div class="sb-container sb-split">
  <div>
    <h2 class="sb-heading">Show how it works</h2>
    <ul class="sb-list">
      <li>✔ First point worth knowing</li>
      <li>✔ Second point worth knowing</li>
      <li>✔ Third point worth knowing</li>
    </ul>
  </div>
  <img class="sb-media" src="${IMG(800, 600)}" alt="">
</div></section>`,
    },
    {
      id: 'content-text', group: 'Content', label: 'Text article',
      description: 'Heading and readable paragraphs (About, policy, article).',
      html: `<section class="sb-section" data-sb-section="content-text"><div class="sb-container sb-narrow">
  <h2 class="sb-heading">About us</h2>
  <p class="sb-lead sb-lead-start">An opening sentence that sets the scene.</p>
  <p class="sb-text">Write your content here. Paragraphs are kept to a comfortable reading width so long text stays easy to read on every screen.</p>
  <h3 class="sb-heading sb-heading-sm">A sub-heading</h3>
  <p class="sb-text">More content. You can add as many paragraphs and headings as you need.</p>
</div></section>`,
    },
    {
      id: 'stats-4', group: 'Social proof', label: 'Numbers',
      description: 'Four key figures.',
      html: `<section class="sb-section sb-section-alt" data-sb-section="stats-4"><div class="sb-container">
  <div class="sb-grid sb-grid-4 sb-center">
    <div><div class="sb-stat-value">10+</div><p class="sb-text sb-muted">Years of experience</p></div>
    <div><div class="sb-stat-value">500</div><p class="sb-text sb-muted">Happy customers</p></div>
    <div><div class="sb-stat-value">24/7</div><p class="sb-text sb-muted">Support</p></div>
    <div><div class="sb-stat-value">99.9%</div><p class="sb-text sb-muted">Uptime</p></div>
  </div>
</div></section>`,
    },
    {
      id: 'testimonials-3', group: 'Social proof', label: 'Testimonials',
      description: 'Three customer quotes.',
      html: `<section class="sb-section" data-sb-section="testimonials-3"><div class="sb-container">
  <div class="sb-center sb-narrow"><h2 class="sb-heading">What our customers say</h2></div>
  <div class="sb-grid">
    <figure class="sb-card sb-quote"><blockquote class="sb-text">“Replace this with a real quote from a customer.”</blockquote><figcaption class="sb-quote-author">Jane Doe <span class="sb-muted">— Company</span></figcaption></figure>
    <figure class="sb-card sb-quote"><blockquote class="sb-text">“Short and specific quotes work best.”</blockquote><figcaption class="sb-quote-author">John Smith <span class="sb-muted">— Company</span></figcaption></figure>
    <figure class="sb-card sb-quote"><blockquote class="sb-text">“Mention a concrete result if you can.”</blockquote><figcaption class="sb-quote-author">Ana López <span class="sb-muted">— Company</span></figcaption></figure>
  </div>
</div></section>`,
    },
    {
      id: 'logos', group: 'Social proof', label: 'Client logos',
      description: 'A row of client or partner names (swap in logo images).',
      html: `<section class="sb-section sb-section-tight" data-sb-section="logos"><div class="sb-container">
  <p class="sb-text sb-muted sb-center">Trusted by</p>
  <div class="sb-logos"><span class="sb-logo-item">ACME</span><span class="sb-logo-item">Globex</span><span class="sb-logo-item">Initech</span><span class="sb-logo-item">Umbrella</span><span class="sb-logo-item">Hooli</span></div>
</div></section>`,
    },
    {
      id: 'steps-3', group: 'Features', label: 'How it works — steps',
      description: 'Three numbered steps.',
      html: `<section class="sb-section" data-sb-section="steps-3"><div class="sb-container">
  <div class="sb-center sb-narrow"><h2 class="sb-heading">How it works</h2></div>
  <div class="sb-grid sb-center">
    <div><div class="sb-step-num">1</div><h3 class="sb-heading sb-heading-sm">Sign up</h3><p class="sb-text sb-muted">Describe the first step.</p></div>
    <div><div class="sb-step-num">2</div><h3 class="sb-heading sb-heading-sm">Set it up</h3><p class="sb-text sb-muted">Describe the second step.</p></div>
    <div><div class="sb-step-num">3</div><h3 class="sb-heading sb-heading-sm">Enjoy</h3><p class="sb-text sb-muted">Describe the result.</p></div>
  </div>
</div></section>`,
    },
    {
      id: 'pricing-3', group: 'Sales', label: 'Pricing — three plans',
      description: 'Three plans; the middle one highlighted.',
      html: `<section class="sb-section sb-section-alt" data-sb-section="pricing-3"><div class="sb-container">
  <div class="sb-center sb-narrow"><h2 class="sb-heading">Simple pricing</h2><p class="sb-text sb-muted">No hidden fees. Cancel anytime.</p></div>
  <div class="sb-grid">
    <div class="sb-card sb-center"><h3 class="sb-heading sb-heading-sm">Basic</h3><div class="sb-price">$9<span class="sb-price-period">/month</span></div><ul class="sb-list"><li>Feature one</li><li>Feature two</li><li>Email support</li></ul><a class="sb-btn sb-btn-outline" href="#">Choose Basic</a></div>
    <div class="sb-card sb-card-featured sb-center"><p class="sb-eyebrow">Most popular</p><h3 class="sb-heading sb-heading-sm">Pro</h3><div class="sb-price">$29<span class="sb-price-period">/month</span></div><ul class="sb-list"><li>Everything in Basic</li><li>Feature three</li><li>Priority support</li></ul><a class="sb-btn" href="#">Choose Pro</a></div>
    <div class="sb-card sb-center"><h3 class="sb-heading sb-heading-sm">Business</h3><div class="sb-price">$79<span class="sb-price-period">/month</span></div><ul class="sb-list"><li>Everything in Pro</li><li>Feature four</li><li>Phone support</li></ul><a class="sb-btn sb-btn-outline" href="#">Contact sales</a></div>
  </div>
</div></section>`,
    },
    {
      id: 'faq', group: 'Sales', label: 'FAQ',
      description: 'Questions that open on click (no script needed).',
      html: `<section class="sb-section" data-sb-section="faq"><div class="sb-container sb-narrow">
  <h2 class="sb-heading sb-center">Frequently asked questions</h2>
  <div class="sb-faq">
    <details class="sb-faq-item"><summary class="sb-faq-q">What is included?</summary><p class="sb-text sb-muted">Answer the question in one or two sentences.</p></details>
    <details class="sb-faq-item"><summary class="sb-faq-q">How do I get started?</summary><p class="sb-text sb-muted">Answer the question in one or two sentences.</p></details>
    <details class="sb-faq-item"><summary class="sb-faq-q">Can I cancel anytime?</summary><p class="sb-text sb-muted">Answer the question in one or two sentences.</p></details>
    <details class="sb-faq-item"><summary class="sb-faq-q">Do you offer support?</summary><p class="sb-text sb-muted">Answer the question in one or two sentences.</p></details>
  </div>
</div></section>`,
    },
    {
      id: 'cta-band', group: 'Sales', label: 'Call to action band',
      description: 'Full-width band in your primary colour.',
      html: `<section class="sb-section sb-section-primary" data-sb-section="cta-band"><div class="sb-container sb-narrow sb-center">
  <h2 class="sb-heading">Ready to get started?</h2>
  <p class="sb-text">One sentence that makes the next step obvious.</p>
  <div class="sb-actions"><a class="sb-btn sb-btn-light" href="#">Contact us</a></div>
</div></section>`,
    },
    {
      id: 'team-4', group: 'Content', label: 'Team',
      description: 'Four people with initials (swap in photos).',
      html: `<section class="sb-section" data-sb-section="team-4"><div class="sb-container">
  <div class="sb-center sb-narrow"><h2 class="sb-heading">Meet the team</h2></div>
  <div class="sb-grid sb-grid-4 sb-center">
    <div><div class="sb-avatar">JD</div><h3 class="sb-heading sb-heading-sm">Jane Doe</h3><p class="sb-text sb-muted">Founder</p></div>
    <div><div class="sb-avatar">JS</div><h3 class="sb-heading sb-heading-sm">John Smith</h3><p class="sb-text sb-muted">Operations</p></div>
    <div><div class="sb-avatar">AL</div><h3 class="sb-heading sb-heading-sm">Ana López</h3><p class="sb-text sb-muted">Design</p></div>
    <div><div class="sb-avatar">MK</div><h3 class="sb-heading sb-heading-sm">Mark Kim</h3><p class="sb-text sb-muted">Support</p></div>
  </div>
</div></section>`,
    },
    {
      id: 'gallery-6', group: 'Content', label: 'Photo gallery',
      description: 'Six images in a responsive grid.',
      html: `<section class="sb-section sb-section-alt" data-sb-section="gallery-6"><div class="sb-container">
  <h2 class="sb-heading sb-center">Gallery</h2>
  <div class="sb-gallery">
    <img class="sb-gallery-img" src="${IMG(600, 400, 'Photo 1')}" alt=""><img class="sb-gallery-img" src="${IMG(600, 400, 'Photo 2')}" alt=""><img class="sb-gallery-img" src="${IMG(600, 400, 'Photo 3')}" alt="">
    <img class="sb-gallery-img" src="${IMG(600, 400, 'Photo 4')}" alt=""><img class="sb-gallery-img" src="${IMG(600, 400, 'Photo 5')}" alt=""><img class="sb-gallery-img" src="${IMG(600, 400, 'Photo 6')}" alt="">
  </div>
</div></section>`,
    },
    {
      id: 'contact-info', group: 'Contact', label: 'Contact details',
      description: 'Phone, email, address and hours.',
      html: `<section class="sb-section" data-sb-section="contact-info"><div class="sb-container">
  <div class="sb-center sb-narrow"><h2 class="sb-heading">Get in touch</h2><p class="sb-text sb-muted">We usually reply within one business day.</p></div>
  <div class="sb-grid">
    <div class="sb-card sb-center"><div class="sb-icon">📞</div><h3 class="sb-heading sb-heading-sm">Phone</h3><p class="sb-text"><a class="sb-link" href="tel:+10000000000">+1 (000) 000-0000</a></p></div>
    <div class="sb-card sb-center"><div class="sb-icon">✉️</div><h3 class="sb-heading sb-heading-sm">Email</h3><p class="sb-text"><a class="sb-link" href="mailto:info@example.com">info@example.com</a></p></div>
    <div class="sb-card sb-center"><div class="sb-icon">📍</div><h3 class="sb-heading sb-heading-sm">Address</h3><p class="sb-text">123 Main Street<br>City, State</p></div>
    <div class="sb-card sb-center"><div class="sb-icon">🕘</div><h3 class="sb-heading sb-heading-sm">Hours</h3><p class="sb-text">Mon–Fri 9:00–17:00</p></div>
  </div>
</div></section>`,
    },
    {
      id: 'contact-form', group: 'Contact', label: 'Contact form',
      description: 'A working form — messages are emailed to you and kept in 📨 Forms.',
      // The only section with a <form>: it posts to /sb-form on the site itself (routed to the panel by
      // the web server), data-sb-form names the form, _hp is the spam honeypot. See siteFormService.ts.
      html: `<section class="sb-section" data-sb-section="contact-form"><div class="sb-container sb-narrow">
  <h2 class="sb-heading sb-center">Send us a message</h2>
  <p class="sb-text sb-muted sb-center">We usually reply within one business day.</p>
  <form class="sb-form" action="/sb-form" method="post" data-sb-form="contact">
    <input type="hidden" name="_form" value="contact">
    <div class="sb-hp" aria-hidden="true"><label>Leave this field empty <input type="text" name="_hp" tabindex="-1" autocomplete="off"></label></div>
    <div class="sb-form-row">
      <label class="sb-field"><span class="sb-label">Name</span><input class="sb-input" type="text" name="name" required maxlength="200" autocomplete="name"></label>
      <label class="sb-field"><span class="sb-label">Email</span><input class="sb-input" type="email" name="email" required maxlength="200" autocomplete="email"></label>
    </div>
    <label class="sb-field"><span class="sb-label">Phone (optional)</span><input class="sb-input" type="tel" name="phone" maxlength="40" autocomplete="tel"></label>
    <label class="sb-field"><span class="sb-label">Message</span><textarea class="sb-input sb-textarea" name="message" rows="5" required maxlength="5000"></textarea></label>
    <div><button class="sb-btn" type="submit">Send message</button></div>
  </form>
</div></section>`,
    },
  ];

  const GROUPS =['Hero', 'Features', 'Content', 'Social proof', 'Sales', 'Contact'];
  const api = { SECTIONS, GROUPS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.SB_SECTIONS = api;
})(typeof window !== 'undefined' ? window : globalThis);
