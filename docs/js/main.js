/**
 * DinoX Website - Main JavaScript
 * Theme Toggle, Mobile Menu, Smooth Scroll, Back to Top, Auto Version Update
 * No external dependencies - pure vanilla JS
 */

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
        // Extract title from ### Added or first ### heading
        let title = 'New Features';
        let items = [];
        
        const lines = body.split('\n');
        for (const line of lines) {
            // Look for main feature heading like "**Volume Controls**"
            const boldMatch = line.match(/^\s*-?\s*\*\*([^*]+)\*\*/);
            if (boldMatch && !title.match(/Volume|Controls|Features/i)) {
                title = boldMatch[1].replace(/ - .*/, '').trim();
            }
            // Look for list items (- item)
            const itemMatch = line.match(/^\s*-\s+(?!\*\*)(.+)$/);
            if (itemMatch) {
                const item = itemMatch[1].trim();
                // Skip items that are just sub-descriptions
                if (item && !item.startsWith('Slider') && !item.startsWith('Works for') && !item.startsWith('Real-time')) {
                    items.push(item);
                }
            }
        }
        
        // If we found a bold title like "**Volume Controls**", use that
        const mainFeatureMatch = body.match(/\*\*([^*]+)\*\*\s*-\s*([^\n]+)/);
        if (mainFeatureMatch) {
            title = mainFeatureMatch[1].trim();
            items = [mainFeatureMatch[2].trim()];
            // Get sub-items
            const subItems = body.match(/^\s+-\s+([^\n*]+)$/gm);
            if (subItems) {
                items = items.concat(subItems.map(s => s.replace(/^\s+-\s+/, '').trim()));
            }
        }
        
        // De-duplicate while preserving order (GitHub release notes sometimes contain repeated bullets)
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
                    ul.innerHTML = items.map(item => `<li>${item}</li>`).join('');
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
                li.textContent = String(entry);
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
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
            </svg>
        `;
        button.title = 'Copy to clipboard';
        button.setAttribute('aria-label', 'Copy to clipboard');
        button.style.cssText = `
            position: absolute;
            top: 4px;
            right: 4px;
            padding: 4px;
            background: var(--bg-card);
            border: 1px solid var(--border-subtle);
            border-radius: var(--radius-sm);
            cursor: pointer;
            opacity: 0;
            transition: opacity 0.2s;
            color: var(--text-secondary);
        `;
        
        pre.style.position = 'relative';
        pre.appendChild(button);

        // Make sure the button is visible for keyboard users.
        pre.addEventListener('focusin', () => {
            button.style.opacity = '1';
        });
        pre.addEventListener('focusout', () => {
            button.style.opacity = '0';
        });

        pre.addEventListener('mouseenter', () => button.style.opacity = '1');
        pre.addEventListener('mouseleave', () => button.style.opacity = '0');

        button.addEventListener('click', async () => {
            const code = pre.querySelector('code').textContent;
            try {
                await navigator.clipboard.writeText(code);
                button.innerHTML = `
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <polyline points="20 6 9 17 4 12"/>
                    </svg>
                `;
                button.style.color = 'var(--color-primary)';
                setTimeout(() => {
                    button.innerHTML = `
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
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

    console.log('DinoX Website initialized');
})();
