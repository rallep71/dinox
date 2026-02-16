/**
 * DinoX Website - Main JavaScript
 * Theme Toggle, Mobile Menu, Smooth Scroll, Back to Top, Auto Version Update
 * No external dependencies - pure vanilla JS
 */

/* Google Translate initialization – must be in global scope */
var _gtScriptLoaded = false;
function googleTranslateElementInit() {
    new google.translate.TranslateElement({
        pageLanguage: 'en',
        includedLanguages: 'de,en,es,fr',
        autoDisplay: false,
        layout: google.translate.TranslateElement.InlineLayout.SIMPLE
    }, 'google_translate_element');
}

function loadGoogleTranslateScript() {
    if (_gtScriptLoaded) return;
    _gtScriptLoaded = true;
    var s = document.createElement('script');
    s.src = 'https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit';
    s.async = true;
    document.body.appendChild(s);
}

(function() {
    'use strict';

    // ===== GitHub Release Auto-Update =====
    const GITHUB_LATEST_API = 'https://api.github.com/repos/rallep71/dinox/releases/latest';
    const GITHUB_RELEASES_API = 'https://api.github.com/repos/rallep71/dinox/releases?per_page=100';
    const VERSION_CACHE_KEY = 'dinox-release-cache';
    const RELEASES_CACHE_KEY = 'dinox-releases-cache';
    const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes
    
    async function fetchLatestRelease() {
        // Check cache first
        const cached = localStorage.getItem(VERSION_CACHE_KEY);
        if (cached) {
            try {
                const { data, timestamp } = JSON.parse(cached);
                if (Date.now() - timestamp < CACHE_DURATION) {
                    return data;
                }
            } catch (e) {
                // Ignore invalid cache
            }
        }
        
        try {
            // Prevent long hangs on slow/blocked networks.
            const controller = ('AbortController' in window) ? new AbortController() : null;
            const timeoutId = controller ? window.setTimeout(() => controller.abort(), 5000) : null;

            const fetchOptions = controller ? { signal: controller.signal } : undefined;
            const response = await fetch(GITHUB_LATEST_API, fetchOptions);
            if (!response.ok) throw new Error('GitHub API error');
            const data = await response.json();

            if (timeoutId) window.clearTimeout(timeoutId);
            
            // Cache the result
            localStorage.setItem(VERSION_CACHE_KEY, JSON.stringify({
                data: data,
                timestamp: Date.now()
            }));
            
            return data;
        } catch (error) {
            console.warn('Could not fetch latest release:', error);
            return null;
        }
    }

    async function fetchReleases() {
        // Check cache first
        const cached = localStorage.getItem(RELEASES_CACHE_KEY);
        if (cached) {
            try {
                const { data, timestamp } = JSON.parse(cached);
                if (Date.now() - timestamp < CACHE_DURATION) {
                    return data;
                }
            } catch (e) {
                // Ignore invalid cache
            }
        }

        try {
            // Prevent long hangs on slow/blocked networks.
            const controller = ('AbortController' in window) ? new AbortController() : null;
            const timeoutId = controller ? window.setTimeout(() => controller.abort(), 5000) : null;

            const fetchOptions = controller ? { signal: controller.signal } : undefined;
            const response = await fetch(GITHUB_RELEASES_API, fetchOptions);
            if (!response.ok) throw new Error('GitHub API error');
            const data = await response.json();

            if (timeoutId) window.clearTimeout(timeoutId);

            // Filter out drafts; keep prereleases (they're still legitimate releases for some users)
            const releases = Array.isArray(data) ? data.filter(r => r && !r.draft) : [];

            // Cache the result
            localStorage.setItem(RELEASES_CACHE_KEY, JSON.stringify({
                data: releases,
                timestamp: Date.now()
            }));

            return releases;
        } catch (error) {
            console.warn('Could not fetch releases list:', error);
            return null;
        }
    }
    
    function formatDate(dateString) {
        const date = new Date(dateString);
        const options = { year: 'numeric', month: 'long', day: 'numeric' };
        return date.toLocaleDateString('en-US', options);
    }
    
    function parseReleaseBody(body) {
        let title = 'New Features';
        let items = [];
        
        const lines = body.split('\n');
        for (const line of lines) {
            // Look for list items (- item)
            // Updated regex to allow items starting with bold text (removed (?!\*\*) )
            const itemMatch = line.match(/^\s*-\s+(.+)$/);
            if (itemMatch) {
                const item = itemMatch[1].trim();
                // Skip items that are just sub-descriptions
                if (item && !item.startsWith('Slider') && !item.startsWith('Works for') && !item.startsWith('Real-time')) {
                    items.push(item);
                }
            }
        }
        
        // Fallback: If no items found, try to extract from "Header - Description" format
        if (items.length === 0) {
            const mainFeatureMatch = body.match(/\*\*([^*]+)\*\*\s*[:\-]\s*([^\n]+)/);
            if (mainFeatureMatch) {
                title = mainFeatureMatch[1].trim();
                items.push(mainFeatureMatch[2].trim());
            }
        } 
        // If exactly one item and it starts with bold, use that as title
        else if (items.length === 1) {
             const singleMatch = items[0].match(/^\*\*([^*]+)\*\*[:\s]+(.+)$/);
             if (singleMatch) {
                 title = singleMatch[1].trim();
                 items[0] = singleMatch[2].trim();
             }
        }
        
        // De-duplicate while preserving order
        const seen = new Set();
        const uniqueItems = [];
        for (const item of items) {
            const key = String(item).trim();
            if (!key) continue;
            if (seen.has(key)) continue;
            seen.add(key);
            uniqueItems.push(item);
        }

        return { title, items: uniqueItems.slice(0, 4) }; // Limit to 4 items
    }
    
    function updateVersionDisplay(release) {
        if (!release) return;
        
        const version = release.tag_name.replace('v', '');
        const date = formatDate(release.published_at);
        
        // Update hero badge
        const heroBadge = document.querySelector('.hero-badge span');
        if (heroBadge) {
            heroBadge.textContent = `Version ${version} available`;
        }
        
        // Update schema.org version
        const schemaScript = document.querySelector('script[type="application/ld+json"]');
        if (schemaScript) {
            try {
                const schema = JSON.parse(schemaScript.textContent);
                schema.softwareVersion = version;
                schemaScript.textContent = JSON.stringify(schema, null, 2);
            } catch (e) {}
        }
        
        // Update XEP section version stat
        const xepVersionStat = document.getElementById('xep-version-stat');
        if (xepVersionStat) {
            const versionNumber = xepVersionStat.querySelector('.xep-stat-number');
            if (versionNumber) versionNumber.textContent = `v${version}`;
        }
        
        // Fallback: update first changelog entry (latest version) with content from release body.
        // If the full releases list loads, it will replace the whole changelog section.
        const firstChangelog = document.querySelector('.changelog-item:first-child');
        if (firstChangelog) {
            const versionSpan = firstChangelog.querySelector('.changelog-version');
            const dateDiv = firstChangelog.querySelector('.changelog-date');
            const contentDiv = firstChangelog.querySelector('.changelog-content');
            
            if (versionSpan) versionSpan.textContent = `v${version}`;
            if (dateDiv) dateDiv.textContent = date;
            
            // Parse and update changelog content from release body
            if (contentDiv && release.body) {
                const { title, items } = parseReleaseBody(release.body);
                const h4 = contentDiv.querySelector('h4');
                const ul = contentDiv.querySelector('ul');
                
                if (h4) h4.textContent = title;
                if (ul && items.length > 0) {
                    ul.innerHTML = items.map(item => {
                        const htmlContent = item.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
                        return `<li>${htmlContent}</li>`;
                    }).join('');
                }
            }
        }
    }

    function renderChangelogFromReleases(releases) {
        if (!Array.isArray(releases) || releases.length === 0) return;

        const changelogList = document.querySelector('.changelog-list');
        if (!changelogList) return;

        // Replace static placeholder/hardcoded entries with GitHub releases.
        changelogList.textContent = '';

        for (const release of releases) {
            if (!release || !release.tag_name) continue;

            const version = release.tag_name;
            const date = release.published_at ? formatDate(release.published_at) : '';

            const item = document.createElement('div');
            item.className = 'changelog-item';

            const versionSpan = document.createElement('span');
            versionSpan.className = 'changelog-version';
            versionSpan.textContent = version;

            const dateDiv = document.createElement('div');
            dateDiv.className = 'changelog-date';
            dateDiv.textContent = date;

            const contentDiv = document.createElement('div');
            contentDiv.className = 'changelog-content';

            const { title, items } = release.body ? parseReleaseBody(release.body) : { title: 'Changes', items: [] };

            const h4 = document.createElement('h4');
            h4.textContent = title || 'Changes';

            const ul = document.createElement('ul');
            const listItems = (items && items.length > 0) ? items.slice(0, 4) : ['See GitHub release notes for details.'];
            for (const entry of listItems) {
                const li = document.createElement('li');
                // Render bold markdown (**text**) as HTML <strong>text</strong>
                li.innerHTML = String(entry).replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
                ul.appendChild(li);
            }

            contentDiv.appendChild(h4);
            contentDiv.appendChild(ul);

            item.appendChild(versionSpan);
            item.appendChild(dateDiv);
            item.appendChild(contentDiv);

            changelogList.appendChild(item);
        }
    }
    
    // Fetch and update on page load
    fetchReleases().then((releases) => {
        if (releases && releases[0]) {
            updateVersionDisplay(releases[0]);
            renderChangelogFromReleases(releases);
            return;
        }

        // Fallback for blocked GitHub API / CORS / privacy tools
        fetchLatestRelease().then(updateVersionDisplay);
    });

    // ===== DOM Elements =====
    const themeToggle = document.getElementById('themeToggle');
    const mobileMenuToggle = document.getElementById('mobileMenuToggle');
    const mobileMenu = document.getElementById('mobileMenu');
    const backToTopBtn = document.getElementById('backToTop');
    const navbar = document.querySelector('.navbar');

    // ===== Theme Management =====
    const THEME_KEY = 'dinox-theme';
    
    function getPreferredTheme() {
        const stored = localStorage.getItem(THEME_KEY);
        if (stored) return stored;
        
        // Default to dark theme
        return 'dark';
    }

    function setTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem(THEME_KEY, theme);

        // Expose state to assistive technology.
        if (themeToggle) {
            themeToggle.setAttribute('aria-pressed', theme === 'dark' ? 'true' : 'false');
        }
    }

    function toggleTheme() {
        const current = document.documentElement.getAttribute('data-theme') || 'light';
        const next = current === 'dark' ? 'light' : 'dark';
        setTheme(next);
    }

    // Initialize theme
    setTheme(getPreferredTheme());

    // Theme toggle click handler
    if (themeToggle) {
        themeToggle.setAttribute('aria-pressed', getPreferredTheme() === 'dark' ? 'true' : 'false');
        themeToggle.addEventListener('click', toggleTheme);
    }

    // Listen for system theme changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
        if (!localStorage.getItem(THEME_KEY)) {
            setTheme(e.matches ? 'dark' : 'light');
        }
    });

    // ===== Mobile Menu =====
    function openMobileMenu() {
        mobileMenu.classList.add('active');
        mobileMenuToggle.classList.add('active');
        mobileMenuToggle.setAttribute('aria-expanded', 'true');
        mobileMenuToggle.setAttribute('aria-label', 'Close menu');
        mobileMenu.setAttribute('aria-hidden', 'false');

        const firstLink = mobileMenu.querySelector('a');
        if (firstLink) firstLink.focus();
    }

    function closeMobileMenu({ restoreFocus = false } = {}) {
        const wasOpen = mobileMenu.classList.contains('active');
        mobileMenu.classList.remove('active');
        mobileMenuToggle.classList.remove('active');
        mobileMenuToggle.setAttribute('aria-expanded', 'false');
        mobileMenuToggle.setAttribute('aria-label', 'Open menu');
        mobileMenu.setAttribute('aria-hidden', 'true');

        if (restoreFocus && wasOpen && mobileMenuToggle) {
            mobileMenuToggle.focus();
        }
    }

    function toggleMobileMenu() {
        const isOpen = mobileMenu.classList.contains('active');
        if (isOpen) {
            closeMobileMenu({ restoreFocus: true });
        } else {
            openMobileMenu();
        }
    }

    if (mobileMenuToggle && mobileMenu) {
        // Provide a consistent baseline state for assistive tech.
        mobileMenuToggle.setAttribute('aria-expanded', 'false');
        mobileMenuToggle.setAttribute('aria-label', 'Open menu');
        mobileMenu.setAttribute('aria-hidden', 'true');

        mobileMenuToggle.addEventListener('click', toggleMobileMenu);

        // Close menu when clicking a link
        mobileMenu.querySelectorAll('a').forEach(link => {
            link.addEventListener('click', () => closeMobileMenu());
        });

        // Close menu when clicking outside
        document.addEventListener('click', (e) => {
            if (!mobileMenu.contains(e.target) && !mobileMenuToggle.contains(e.target)) {
                closeMobileMenu({ restoreFocus: false });
            }
        });

        // Close menu on escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && mobileMenu.classList.contains('active')) {
                closeMobileMenu({ restoreFocus: true });
            }
        });

        // Trap Tab focus inside the mobile menu while it's open.
        document.addEventListener('keydown', (e) => {
            if (e.key !== 'Tab') return;
            if (!mobileMenu.classList.contains('active')) return;

            const focusables = [mobileMenuToggle, ...Array.from(mobileMenu.querySelectorAll('a, button'))]
                .filter(Boolean);
            if (focusables.length === 0) return;

            const first = focusables[0];
            const last = focusables[focusables.length - 1];
            const active = document.activeElement;

            // If focus is outside the menu/toggle, bring it back in.
            if (!mobileMenu.contains(active) && active !== mobileMenuToggle) {
                e.preventDefault();
                (e.shiftKey ? last : first).focus();
                return;
            }

            if (e.shiftKey) {
                if (active === first) {
                    e.preventDefault();
                    last.focus();
                }
            } else {
                if (active === last) {
                    e.preventDefault();
                    first.focus();
                }
            }
        });

        // Also guard against programmatic focus leaving the menu while open.
        document.addEventListener('focusin', (e) => {
            if (!mobileMenu.classList.contains('active')) return;
            const target = e.target;
            if (mobileMenu.contains(target) || target === mobileMenuToggle) return;

            const firstLink = mobileMenu.querySelector('a');
            if (firstLink) firstLink.focus();
        });
    }

    // ===== Smooth Scroll =====
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            const targetId = this.getAttribute('href');
            if (targetId === '#') return;
            
            const target = document.querySelector(targetId);
            if (target) {
                e.preventDefault();
                const navHeight = navbar ? navbar.offsetHeight : 0;
                const targetPosition = target.getBoundingClientRect().top + window.pageYOffset - navHeight - 20;

                const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
                const isSkipLink = this.classList && this.classList.contains('skip-link');
                
                window.scrollTo({
                    top: targetPosition,
                    behavior: (prefersReducedMotion || isSkipLink) ? 'auto' : 'smooth'
                });

                // Move focus to the target for keyboard/screen reader users.
                // If the target isn't normally focusable (e.g. <section>), make it programmatically focusable.
                if (!target.hasAttribute('tabindex')) {
                    target.setAttribute('tabindex', '-1');
                }
                // PreventScroll avoids fighting the smooth scrolling.
                setTimeout(() => {
                    try {
                        target.focus({ preventScroll: true });
                    } catch (_) {
                        target.focus();
                    }
                }, 0);

                // Update URL without jumping
                history.pushState(null, null, targetId);
            }
        });
    });

    // ===== Back to Top Button =====
    function updateBackToTop() {
        if (!backToTopBtn) return;
        
        if (window.pageYOffset > 400) {
            backToTopBtn.classList.add('visible');
        } else {
            backToTopBtn.classList.remove('visible');
        }
    }

    if (backToTopBtn) {
        backToTopBtn.addEventListener('click', () => {
            const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
            window.scrollTo({
                top: 0,
                behavior: prefersReducedMotion ? 'auto' : 'smooth'
            });
        });
    }

    // ===== Navbar Shadow on Scroll =====
    function updateNavbar() {
        if (!navbar) return;
        
        if (window.pageYOffset > 10) {
            navbar.style.boxShadow = 'var(--shadow-md)';
        } else {
            navbar.style.boxShadow = 'none';
        }
    }

    // ===== Scroll Event Handler =====
    let ticking = false;
    
    function onScroll() {
        if (!ticking) {
            window.requestAnimationFrame(() => {
                updateBackToTop();
                updateNavbar();
                ticking = false;
            });
            ticking = true;
        }
    }

    window.addEventListener('scroll', onScroll, { passive: true });

    // ===== Intersection Observer for Animations =====
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const fadeTargets = document.querySelectorAll('.feature-card, .download-card, .xep-category, .stat-card');

    if (!prefersReducedMotion && ('IntersectionObserver' in window)) {
        const fadeObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('fade-in-up');
                    fadeObserver.unobserve(entry.target);
                }
            });
        }, observerOptions);

        // Observe elements for fade-in animation.
        // Avoid hiding content that is already in the initial viewport.
        fadeTargets.forEach(el => {
            const rect = el.getBoundingClientRect();
            const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
            const inViewport = rect.top < viewportHeight && rect.bottom > 0;

            if (!inViewport) {
                el.style.opacity = '0';
                fadeObserver.observe(el);
            }
        });

        // If a user tabs into a target before it becomes visible, ensure it's shown.
        document.addEventListener('focusin', (e) => {
            const container = e.target.closest('.feature-card, .download-card, .xep-category, .stat-card');
            if (!container) return;
            if (container.style.opacity === '0') {
                container.style.opacity = '1';
                container.classList.add('fade-in-up');
                fadeObserver.unobserve(container);
            }
        });
    } else {
        // Reduced motion (or no observer support): keep content visible.
        fadeTargets.forEach(el => {
            el.style.opacity = '1';
        });
    }

    // ===== Copy Code to Clipboard =====
    document.querySelectorAll('.download-card pre').forEach(pre => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'copy-btn';
        button.innerHTML = `
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
            </svg>
        `;
        button.title = 'Copy to clipboard';
        button.setAttribute('aria-label', 'Copy to clipboard');
        // Styling is handled in CSS to ensure consistent visibility and sizing.
        
        pre.style.position = 'relative';
        pre.appendChild(button);

        button.addEventListener('click', async () => {
            const code = pre.querySelector('code').textContent;
            try {
                await navigator.clipboard.writeText(code);
                button.innerHTML = `
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false">
                        <polyline points="20 6 9 17 4 12"/>
                    </svg>
                `;
                button.style.color = 'var(--color-primary)';
                setTimeout(() => {
                    button.innerHTML = `
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false">
                            <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
                        </svg>
                    `;
                    button.style.color = 'var(--text-secondary)';
                }, 2000);
            } catch (err) {
                console.error('Copy failed:', err);
            }
        });
    });

    // ===== External Links =====
    document.querySelectorAll('a[href^="http"]').forEach(link => {
        if (!link.href.includes(window.location.hostname)) {
            // Do NOT force opening in a new tab/window (WCAG: avoid unexpected context changes).
            // If the author explicitly uses target="_blank", ensure it is safe and announced.
            if ((link.getAttribute('target') || '').toLowerCase() === '_blank') {
                const existingRel = link.getAttribute('rel') || '';
                const relParts = new Set(existingRel.split(/\s+/).filter(Boolean));
                relParts.add('noopener');
                relParts.add('noreferrer');
                link.setAttribute('rel', Array.from(relParts).join(' '));

                // Add a screen-reader hint once.
                if (!link.querySelector('.sr-only')) {
                    const hint = document.createElement('span');
                    hint.className = 'sr-only';
                    hint.textContent = ' (opens in a new tab)';
                    link.appendChild(hint);
                }
            }
        }
    });

    // ===== Initial state =====
    updateBackToTop();
    updateNavbar();

    // ===== Hero Slider =====
    const heroSlides = document.querySelectorAll('.hero-slide');
    const heroDotsContainer = document.querySelector('.hero-slider-dots');
    
    if (heroSlides.length > 0 && heroDotsContainer) {
        let currentSlide = 0;
        
        // Create dots
        heroSlides.forEach((_, i) => {
            const dot = document.createElement('button');
            dot.type = 'button';
            dot.classList.add('hero-slider-dot');
            if (i === 0) dot.classList.add('active');
            dot.setAttribute('aria-label', `Go to slide ${i + 1} of ${heroSlides.length}`);
            dot.addEventListener('click', () => goToSlide(i));
            heroDotsContainer.appendChild(dot);
        });
        
        const heroDots = document.querySelectorAll('.hero-slider-dot');
        
        function goToSlide(index) {
            heroSlides[currentSlide].classList.remove('active');
            heroSlides[currentSlide].setAttribute('aria-hidden', 'true');
            heroDots[currentSlide].classList.remove('active');
            heroDots[currentSlide].removeAttribute('aria-current');
            currentSlide = index;
            heroSlides[currentSlide].classList.add('active');
            heroSlides[currentSlide].setAttribute('aria-hidden', 'false');
            heroDots[currentSlide].classList.add('active');
            heroDots[currentSlide].setAttribute('aria-current', 'true');
        }

        // For accessibility (pause/stop requirement), do not auto-advance.
        heroSlides.forEach((slide, i) => slide.setAttribute('aria-hidden', i === 0 ? 'false' : 'true'));
        heroDots[0].setAttribute('aria-current', 'true');
    }

    // ===== Lightbox for Screenshots =====
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightboxImg');
    const lightboxCaption = document.getElementById('lightboxCaption');
    const lightboxClose = document.querySelector('.lightbox-close');
    
    if (lightbox && lightboxImg) {
        let lastFocusedElement = null;
        let backgroundElements = [];

        function setBackgroundInert(isInert) {
            if (isInert) {
                backgroundElements = Array.from(document.body.children)
                    .filter(el => el !== lightbox && el.tagName !== 'SCRIPT');

                backgroundElements.forEach(el => {
                    if (!el.hasAttribute('data-prev-aria-hidden')) {
                        const prev = el.getAttribute('aria-hidden');
                        el.setAttribute('data-prev-aria-hidden', prev === null ? '' : prev);
                    }
                    if (!el.hasAttribute('data-prev-pointer-events')) {
                        el.setAttribute('data-prev-pointer-events', el.style.pointerEvents || '');
                    }

                    el.setAttribute('aria-hidden', 'true');
                    // Best effort: supported browsers will prevent all interaction.
                    // Fallback: also block pointer interactions.
                    try {
                        el.inert = true;
                    } catch (_) {
                        // Ignore if inert isn't supported.
                    }
                    el.style.pointerEvents = 'none';
                });
            } else {
                backgroundElements.forEach(el => {
                    const prevAriaHidden = el.getAttribute('data-prev-aria-hidden');
                    if (prevAriaHidden === '') {
                        el.removeAttribute('aria-hidden');
                    } else if (prevAriaHidden !== null) {
                        el.setAttribute('aria-hidden', prevAriaHidden);
                    }
                    el.removeAttribute('data-prev-aria-hidden');

                    const prevPointerEvents = el.getAttribute('data-prev-pointer-events');
                    el.style.pointerEvents = prevPointerEvents || '';
                    el.removeAttribute('data-prev-pointer-events');

                    try {
                        el.inert = false;
                    } catch (_) {
                        // Ignore if inert isn't supported.
                    }
                });
                backgroundElements = [];
            }
        }

        function getLightboxFocusableElements() {
            return Array.from(lightbox.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'))
                .filter(el => !el.hasAttribute('disabled') && el.getAttribute('aria-hidden') !== 'true');
        }

        // Open lightbox on screenshot click
        document.querySelectorAll('.screenshot-trigger').forEach(trigger => {
            trigger.addEventListener('click', () => {
                const item = trigger.closest('.screenshot-item');
                const img = item ? item.querySelector('img') : null;
                const caption = item ? item.querySelector('.caption') : null;

                if (!img) return;

                lastFocusedElement = document.activeElement;
                lightboxImg.src = img.src;
                lightboxImg.alt = img.alt;
                lightboxCaption.textContent = caption ? caption.textContent : '';
                lightbox.classList.add('active');
                document.body.style.overflow = 'hidden';
                setBackgroundInert(true);

                // Focus the close button for a predictable keyboard starting point.
                if (lightboxClose) {
                    lightboxClose.focus();
                } else {
                    lightbox.focus();
                }
            });
        });
        
        // Close lightbox
        function closeLightbox() {
            lightbox.classList.remove('active');
            document.body.style.overflow = '';
            setBackgroundInert(false);

            // Restore focus to the element that opened the dialog.
            if (lastFocusedElement && typeof lastFocusedElement.focus === 'function') {
                lastFocusedElement.focus();
            }
        }

        if (lightboxClose) {
            lightboxClose.addEventListener('click', closeLightbox);
        }

        // Backdrop click closes; clicks inside content should not.
        lightbox.addEventListener('click', (e) => {
            if (e.target === lightbox) closeLightbox();
        });

        document.addEventListener('keydown', (e) => {
            if (!lightbox.classList.contains('active')) return;

            if (e.key === 'Escape') {
                closeLightbox();
                return;
            }

            if (e.key === 'Tab') {
                const focusable = getLightboxFocusableElements();
                if (focusable.length === 0) {
                    e.preventDefault();
                    return;
                }

                const first = focusable[0];
                const last = focusable[focusable.length - 1];
                const active = document.activeElement;

                if (e.shiftKey) {
                    if (active === first || active === lightbox) {
                        e.preventDefault();
                        last.focus();
                    }
                } else {
                    if (active === last) {
                        e.preventDefault();
                        first.focus();
                    }
                }
            }
        });
    }

    // ========================================
    // Google Translate Language Switcher
    // ========================================
    (function initLanguageSwitcher() {
        const allBtns = document.querySelectorAll('.lang-btn');

        function getActiveLanguage() {
            const cookie = document.cookie.split(';')
                .map(c => c.trim())
                .find(c => c.startsWith('googtrans='));
            if (cookie) {
                const parts = cookie.split('/');
                return parts[parts.length - 1] || 'en';
            }
            return 'en';
        }

        function setActiveState(lang) {
            allBtns.forEach(btn => {
                const isActive = btn.getAttribute('data-lang') === lang;
                btn.classList.toggle('active', isActive);
                btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
            });
        }

        function switchLanguage(lang) {
            if (lang === 'en') {
                // Remove googtrans cookie to revert to original
                document.cookie = 'googtrans=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/';
                document.cookie = 'googtrans=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/; domain=.' + window.location.hostname;
            } else {
                // Lazy-load Google Translate script on first non-EN selection
                loadGoogleTranslateScript();
                document.cookie = 'googtrans=/en/' + lang + '; path=/';
                document.cookie = 'googtrans=/en/' + lang + '; path=/; domain=.' + window.location.hostname;
            }
            setActiveState(lang);
            window.location.reload();
        }

        allBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                const lang = btn.getAttribute('data-lang');
                if (lang) switchLanguage(lang);
            });
        });

        // Set initial active state from cookie
        var activeLang = getActiveLanguage();
        setActiveState(activeLang);
        // Load Google Translate if a non-EN language is already active (from cookie)
        if (activeLang !== 'en') {
            loadGoogleTranslateScript();
        }
    })();

    // ========================================
    // Documentation Viewer (fetch + render MD)
    // ========================================
    (function initDocsViewer() {
        const BASE_RAW = 'https://raw.githubusercontent.com/rallep71/dinox/master/docs/internal/';
        const BASE_VIEW = 'https://github.com/rallep71/dinox/blob/master/docs/internal/';
        const CACHE_TTL = 10 * 60 * 1000; // 10 minutes

        const viewer = document.getElementById('docsViewer');
        const viewerTitle = document.getElementById('docsViewerTitle');
        const viewerBody = document.getElementById('docsViewerBody');
        const viewerClose = document.getElementById('docsViewerClose');
        const viewerGithub = document.getElementById('docsViewerGithub');
        const cards = document.querySelectorAll('.docs-card[data-doc]');

        if (!viewer || cards.length === 0) return;

        // --- Lightweight Markdown to HTML renderer ---
        function mdToHtml(md) {
            // Normalize line endings
            md = md.replace(/\r\n/g, '\n');

            let html = '';
            const lines = md.split('\n');
            let i = 0;

            function escHtml(s) {
                return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
            }

            function inlineMarkdown(text) {
                // Images
                text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" loading="lazy">');
                // Links
                text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
                // Bold + italic
                text = text.replace(/\*\*\*([^*]+)\*\*\*/g, '<strong><em>$1</em></strong>');
                // Bold
                text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
                // Italic
                text = text.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>');
                // Inline code
                text = text.replace(/`([^`]+)`/g, function(_, code) {
                    return '<code>' + escHtml(code) + '</code>';
                });
                return text;
            }

            while (i < lines.length) {
                const line = lines[i];

                // Fenced code block
                const fenceMatch = line.match(/^```(\w*)/);
                if (fenceMatch) {
                    i++;
                    let codeLines = [];
                    while (i < lines.length && !lines[i].startsWith('```')) {
                        codeLines.push(escHtml(lines[i]));
                        i++;
                    }
                    i++; // skip closing ```
                    html += '<pre><code>' + codeLines.join('\n') + '</code></pre>\n';
                    continue;
                }

                // Horizontal rule
                if (/^(-{3,}|_{3,}|\*{3,})\s*$/.test(line)) {
                    html += '<hr>\n';
                    i++;
                    continue;
                }

                // Headings
                const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);
                if (headingMatch) {
                    const level = headingMatch[1].length;
                    html += '<h' + level + '>' + inlineMarkdown(headingMatch[2]) + '</h' + level + '>\n';
                    i++;
                    continue;
                }

                // Table
                if (line.includes('|') && i + 1 < lines.length && /^\|?\s*[-:]+[-|:\s]+$/.test(lines[i + 1])) {
                    html += '<table>\n';
                    // Header row
                    const headerCells = line.split('|').map(c => c.trim()).filter(c => c !== '');
                    html += '<thead><tr>' + headerCells.map(c => '<th>' + inlineMarkdown(c) + '</th>').join('') + '</tr></thead>\n';
                    i += 2; // skip header + separator
                    html += '<tbody>\n';
                    while (i < lines.length && lines[i].includes('|') && lines[i].trim() !== '') {
                        const cells = lines[i].split('|').map(c => c.trim()).filter(c => c !== '');
                        html += '<tr>' + cells.map(c => '<td>' + inlineMarkdown(c) + '</td>').join('') + '</tr>\n';
                        i++;
                    }
                    html += '</tbody></table>\n';
                    continue;
                }

                // Blockquote
                if (line.startsWith('>')) {
                    let quoteLines = [];
                    while (i < lines.length && lines[i].startsWith('>')) {
                        quoteLines.push(lines[i].replace(/^>\s?/, ''));
                        i++;
                    }
                    html += '<blockquote><p>' + inlineMarkdown(quoteLines.join(' ')) + '</p></blockquote>\n';
                    continue;
                }

                // Unordered list
                if (/^\s*[-*+]\s+/.test(line)) {
                    html += '<ul>\n';
                    while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i])) {
                        const item = lines[i].replace(/^\s*[-*+]\s+/, '');
                        html += '<li>' + inlineMarkdown(item) + '</li>\n';
                        i++;
                    }
                    html += '</ul>\n';
                    continue;
                }

                // Ordered list
                if (/^\s*\d+\.\s+/.test(line)) {
                    html += '<ol>\n';
                    while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
                        const item = lines[i].replace(/^\s*\d+\.\s+/, '');
                        html += '<li>' + inlineMarkdown(item) + '</li>\n';
                        i++;
                    }
                    html += '</ol>\n';
                    continue;
                }

                // Empty line
                if (line.trim() === '') {
                    i++;
                    continue;
                }

                // Paragraph — collect consecutive non-empty lines
                let paraLines = [];
                while (i < lines.length && lines[i].trim() !== '' &&
                       !lines[i].startsWith('#') && !lines[i].startsWith('```') &&
                       !/^\s*[-*+]\s+/.test(lines[i]) && !/^\s*\d+\.\s+/.test(lines[i]) &&
                       !lines[i].startsWith('>') && !/^(-{3,}|_{3,}|\*{3,})\s*$/.test(lines[i]) &&
                       !(lines[i].includes('|') && i + 1 < lines.length && /^\|?\s*[-:]+[-|:\s]+$/.test(lines[i + 1]))) {
                    paraLines.push(lines[i]);
                    i++;
                }
                if (paraLines.length > 0) {
                    html += '<p>' + inlineMarkdown(paraLines.join('\n').replace(/\n/g, '<br>')) + '</p>\n';
                }
            }

            return html;
        }

        // --- Fetch, cache & display ---
        const docCache = {};

        function fetchDoc(name) {
            var cached = docCache[name];
            if (cached && Date.now() - cached.ts < CACHE_TTL) {
                return Promise.resolve(cached.html);
            }

            var url = BASE_RAW + name + '.md';
            // Abort after 15 seconds to avoid hanging spinner
            var controller = ('AbortController' in window) ? new AbortController() : null;
            var timeoutId = controller ? window.setTimeout(function() { controller.abort(); }, 15000) : null;
            var fetchOpts = controller ? { signal: controller.signal } : undefined;

            return fetch(url, fetchOpts)
                .then(function(res) {
                    if (timeoutId) window.clearTimeout(timeoutId);
                    if (!res.ok) throw new Error('HTTP ' + res.status);
                    return res.text();
                })
                .then(function(md) {
                    try {
                        var rendered = mdToHtml(md);
                        docCache[name] = { html: rendered, ts: Date.now() };
                        return rendered;
                    } catch (parseErr) {
                        console.warn('Markdown parse error:', parseErr);
                        // Fallback: wrap raw text in <pre>
                        var safe = md.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                        return '<pre style="white-space:pre-wrap;word-break:break-word;">' + safe + '</pre>';
                    }
                });
        }

        function showDoc(name, title) {
            // Set active card
            cards.forEach(function(c) { c.classList.toggle('active', c.getAttribute('data-doc') === name); });

            viewerTitle.textContent = title;
            viewerGithub.href = BASE_VIEW + name + '.md';
            viewerBody.innerHTML = '<div class="docs-viewer-loading" aria-live="polite">Loading documentation...</div>';
            viewer.hidden = false;

            fetchDoc(name)
                .then(function(html) {
                    viewerBody.innerHTML = html;
                })
                .catch(function(err) {
                    viewerBody.innerHTML = '<div class="docs-viewer-error">Failed to load document. <a href="' +
                        BASE_VIEW + name + '.md" target="_blank" rel="noopener noreferrer">View on GitHub</a> instead.</div>';
                    console.warn('Docs fetch error:', err);
                });

            // Scroll viewer into view
            viewer.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }

        function closeViewer() {
            viewer.hidden = true;
            cards.forEach(function(c) { c.classList.remove('active'); });
        }

        // Card click handlers
        cards.forEach(function(card) {
            card.addEventListener('click', function() {
                var name = card.getAttribute('data-doc');
                var title = card.querySelector('h3').textContent;
                showDoc(name, title);
            });
            card.addEventListener('keydown', function(e) {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    card.click();
                }
            });
        });

        // Close button
        if (viewerClose) {
            viewerClose.addEventListener('click', closeViewer);
        }

        // Open doc from URL hash (e.g. #docs/SECURITY)
        var hashMatch = window.location.hash.match(/^#docs\/(\w+)$/);
        if (hashMatch) {
            var docName = hashMatch[1];
            var matchingCard = document.querySelector('.docs-card[data-doc="' + docName + '"]');
            if (matchingCard) {
                var cardTitle = matchingCard.querySelector('h3').textContent;
                setTimeout(function() { showDoc(docName, cardTitle); }, 300);
            }
        }
    })();

    console.log('DinoX Website initialized');
})();
