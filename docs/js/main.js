/**
 * DinoX Website - Main JavaScript
 * Theme Toggle, Mobile Menu, Smooth Scroll, Back to Top, Auto Version Update
 * No external dependencies - pure vanilla JS
 */

(function() {
    'use strict';

    // ===== GitHub Release Auto-Update =====
    const GITHUB_API = 'https://api.github.com/repos/rallep71/dinox/releases/latest';
    const VERSION_CACHE_KEY = 'dinox-release-cache';
    const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes
    
    async function fetchLatestRelease() {
        // Check cache first
        const cached = localStorage.getItem(VERSION_CACHE_KEY);
        if (cached) {
            const { data, timestamp } = JSON.parse(cached);
            if (Date.now() - timestamp < CACHE_DURATION) {
                return data;
            }
        }
        
        try {
            const response = await fetch(GITHUB_API);
            if (!response.ok) throw new Error('GitHub API error');
            const data = await response.json();
            
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
        
        return { title, items: items.slice(0, 4) }; // Limit to 4 items
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
        
        // Update first changelog entry (latest version) with content from release body
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
    
    // Fetch and update on page load
    fetchLatestRelease().then(updateVersionDisplay);

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
        themeToggle.addEventListener('click', toggleTheme);
    }

    // Listen for system theme changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
        if (!localStorage.getItem(THEME_KEY)) {
            setTheme(e.matches ? 'dark' : 'light');
        }
    });

    // ===== Mobile Menu =====
    function toggleMobileMenu() {
        const isOpen = mobileMenu.classList.contains('active');
        mobileMenu.classList.toggle('active');
        mobileMenuToggle.classList.toggle('active');
        mobileMenuToggle.setAttribute('aria-expanded', !isOpen);
    }

    function closeMobileMenu() {
        mobileMenu.classList.remove('active');
        mobileMenuToggle.classList.remove('active');
        mobileMenuToggle.setAttribute('aria-expanded', 'false');
    }

    if (mobileMenuToggle && mobileMenu) {
        mobileMenuToggle.addEventListener('click', toggleMobileMenu);

        // Close menu when clicking a link
        mobileMenu.querySelectorAll('a').forEach(link => {
            link.addEventListener('click', closeMobileMenu);
        });

        // Close menu when clicking outside
        document.addEventListener('click', (e) => {
            if (!mobileMenu.contains(e.target) && !mobileMenuToggle.contains(e.target)) {
                closeMobileMenu();
            }
        });

        // Close menu on escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                closeMobileMenu();
            }
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
                
                window.scrollTo({
                    top: targetPosition,
                    behavior: 'smooth'
                });

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
            window.scrollTo({
                top: 0,
                behavior: 'smooth'
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

    const fadeObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('fade-in-up');
                fadeObserver.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Observe elements for fade-in animation
    document.querySelectorAll('.feature-card, .download-card, .xep-category, .stat-card').forEach(el => {
        el.style.opacity = '0';
        fadeObserver.observe(el);
    });

    // ===== Copy Code to Clipboard =====
    document.querySelectorAll('.download-card pre').forEach(pre => {
        const button = document.createElement('button');
        button.className = 'copy-btn';
        button.innerHTML = `
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
            </svg>
        `;
        button.title = 'In Zwischenablage kopieren';
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
            link.setAttribute('target', '_blank');
            link.setAttribute('rel', 'noopener noreferrer');
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
            dot.classList.add('hero-slider-dot');
            if (i === 0) dot.classList.add('active');
            dot.addEventListener('click', () => goToSlide(i));
            heroDotsContainer.appendChild(dot);
        });
        
        const heroDots = document.querySelectorAll('.hero-slider-dot');
        
        function goToSlide(index) {
            heroSlides[currentSlide].classList.remove('active');
            heroDots[currentSlide].classList.remove('active');
            currentSlide = index;
            heroSlides[currentSlide].classList.add('active');
            heroDots[currentSlide].classList.add('active');
        }
        
        function nextSlide() {
            goToSlide((currentSlide + 1) % heroSlides.length);
        }
        
        // Auto-advance every 4 seconds
        setInterval(nextSlide, 4000);
    }

    // ===== Lightbox for Screenshots =====
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightboxImg');
    const lightboxCaption = document.getElementById('lightboxCaption');
    const lightboxClose = document.querySelector('.lightbox-close');
    
    if (lightbox && lightboxImg) {
        // Open lightbox on screenshot click
        document.querySelectorAll('.screenshot-item').forEach(item => {
            item.addEventListener('click', () => {
                const img = item.querySelector('img');
                const caption = item.querySelector('.caption');
                
                lightboxImg.src = img.src;
                lightboxImg.alt = img.alt;
                lightboxCaption.textContent = caption ? caption.textContent : '';
                lightbox.classList.add('active');
                document.body.style.overflow = 'hidden';
            });
        });
        
        // Close lightbox
        function closeLightbox() {
            lightbox.classList.remove('active');
            document.body.style.overflow = '';
        }
        
        // Click anywhere (including image) closes lightbox
        lightbox.addEventListener('click', closeLightbox);
        
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && lightbox.classList.contains('active')) {
                closeLightbox();
            }
        });
    }

    console.log('DinoX Website initialized');
})();
