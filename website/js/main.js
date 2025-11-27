// Theme Toggle
const themeToggle = document.getElementById('themeToggle');
const html = document.documentElement;

// Load saved theme or detect system preference
const savedTheme = localStorage.getItem('theme');
const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
const initialTheme = savedTheme || (systemPrefersDark ? 'dark' : 'light');

html.setAttribute('data-theme', initialTheme);

if (themeToggle) {
    themeToggle.addEventListener('click', () => {
    const currentTheme = html.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    
    html.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);
});
}

// Mobile Menu Toggle
const mobileMenuToggle = document.getElementById('mobileMenuToggle');
const navMenu = document.getElementById('navMenu') || document.querySelector('.nav-menu');

if (mobileMenuToggle && navMenu) {
    // init aria-hidden depending on viewport width
    const initAriaHidden = () => {
        if (window.innerWidth <= 768) {
            navMenu.setAttribute('aria-hidden', 'true');
            mobileMenuToggle.setAttribute('aria-expanded', 'false');
        } else {
            navMenu.setAttribute('aria-hidden', 'false');
            mobileMenuToggle.setAttribute('aria-expanded', 'false');
            navMenu.classList.remove('active');
            mobileMenuToggle.classList.remove('active');
        }
    };
    initAriaHidden();
    window.addEventListener('resize', initAriaHidden);

    mobileMenuToggle.addEventListener('click', () => {
    const isActive = navMenu.classList.toggle('active');
    mobileMenuToggle.classList.toggle('active');
    mobileMenuToggle.setAttribute('aria-expanded', isActive ? 'true' : 'false');
    navMenu.setAttribute('aria-hidden', isActive ? 'false' : 'true');
});
}

// Close mobile menu when clicking outside
document.addEventListener('click', (e) => {
    if (navMenu && mobileMenuToggle && !navMenu.contains(e.target) && !mobileMenuToggle.contains(e.target)) {
        navMenu.classList.remove('active');
        mobileMenuToggle.classList.remove('active');
        mobileMenuToggle.setAttribute('aria-expanded', 'false');
    }
});

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
            // Close mobile menu if open
            if (navMenu) navMenu.classList.remove('active');
            if (mobileMenuToggle) mobileMenuToggle.classList.remove('active');
            if (mobileMenuToggle) mobileMenuToggle.setAttribute('aria-expanded', 'false');
        }
    });
});

// Back to Top Button
const backToTop = document.getElementById('backToTop');
if (backToTop) {
    const scrollHandler = () => {
        if (window.scrollY > 300) {
            backToTop.classList.add('visible');
        } else {
            backToTop.classList.remove('visible');
        }
    };
    window.addEventListener('scroll', scrollHandler);
    // Initialize
    scrollHandler();

    backToTop.addEventListener('click', () => {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    });
    // Make toggle keyboard accessible (Enter/Space)
    mobileMenuToggle.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ' || e.key === 'Spacebar') {
            e.preventDefault();
            mobileMenuToggle.click();
        }
    });
    // Close on Escape
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (navMenu.classList.contains('active')) {
                navMenu.classList.remove('active');
                mobileMenuToggle.classList.remove('active');
                mobileMenuToggle.setAttribute('aria-expanded', 'false');
                navMenu.setAttribute('aria-hidden', 'true');
            }
        }
    });
}

// Intersection Observer for fade-in animations
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, observerOptions);

// Observe elements with fade-in animation
document.querySelectorAll('.feature-card, .doc-card, .download-card').forEach(el => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(20px)';
    el.style.transition = 'opacity 0.6s ease-out, transform 0.6s ease-out';
    observer.observe(el);
});

// Add active class to nav links based on scroll position
const sections = document.querySelectorAll('section[id]');
const navLinks = document.querySelectorAll('.nav-menu a[href^="#"]');

window.addEventListener('scroll', () => {
    let current = '';
    
    sections.forEach(section => {
        const sectionTop = section.offsetTop;
        const sectionHeight = section.clientHeight;
        if (window.pageYOffset >= sectionTop - 100) {
            current = section.getAttribute('id');
        }
    });
    
    navLinks.forEach(link => {
        link.classList.remove('active');
        link.removeAttribute('aria-current');
        if (link.getAttribute('href') === `#${current}`) {
            link.classList.add('active');
            link.setAttribute('aria-current', 'true');
        }
    });
});

// Highlight active link in docs sidebar
const asideLinks = document.querySelectorAll('.docs-aside a');
const drawerLinks = document.querySelectorAll('.docs-drawer a');
if (asideLinks.length) {
    const current = window.location.pathname.split('/').pop() || 'index.html';
    asideLinks.forEach(link => {
        const href = link.getAttribute('href');
        if (href === current) {
            link.classList.add('active');
        }
    });
}
if (drawerLinks.length) {
    const current = window.location.pathname.split('/').pop() || 'index.html';
    drawerLinks.forEach(link => {
        const href = link.getAttribute('href');
        if (href === current) {
            link.classList.add('active');
        }
    });
}

// Smooth scroll polyfill for internal section links on docs pages (when Base is set)
document.querySelectorAll('.docs-aside a, a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        const href = this.getAttribute('href');
        if (!href) return;
        // If it's a local anchor, perform smooth scroll
        if (href.startsWith('#')) {
            e.preventDefault();
            const target = document.querySelector(href);
            if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
        // Else default navigation, sidebar link will handle the route
    });
});

// Docs Drawer (mobile) -- drawer overlay + accessible focus trapping
const docsDrawerToggle = document.getElementById('docsDrawerToggle');
const docsDrawer = document.getElementById('docsDrawer');
const docsDrawerOverlay = document.getElementById('docsDrawerOverlay');
const docsDrawerClose = docsDrawer && docsDrawer.querySelector('.close-drawer');
if (docsDrawerToggle && docsDrawer && docsDrawerOverlay) {
    const focusableSelector = 'a, button, input, textarea, select, [tabindex]:not([tabindex="-1"])';
    let lastFocused = null;

    const openDrawer = () => {
        lastFocused = document.activeElement;
        docsDrawer.classList.add('open');
        docsDrawerOverlay.classList.add('open');
        document.body.classList.add('drawer-open');
        docsDrawerToggle.setAttribute('aria-expanded', 'true');
        docsDrawerToggle.classList.add('active');
        docsDrawer.setAttribute('aria-hidden', 'false');
        // focus first link
        const first = docsDrawer.querySelector(focusableSelector);
        if (first) setTimeout(() => first.focus(), 50);
        // trap focus
        docsDrawer.addEventListener('keydown', trapTab);
    };

    const closeDrawer = () => {
        docsDrawer.classList.remove('open');
        docsDrawerOverlay.classList.remove('open');
        document.body.classList.remove('drawer-open');
        docsDrawerToggle.setAttribute('aria-expanded', 'false');
        docsDrawerToggle.classList.remove('active');
        docsDrawer.setAttribute('aria-hidden', 'true');
        if (lastFocused) lastFocused.focus();
        docsDrawer.removeEventListener('keydown', trapTab);
    };

    const trapTab = (e) => {
        if (e.key !== 'Tab') return;
        const focusable = Array.from(docsDrawer.querySelectorAll(focusableSelector));
        if (!focusable.length) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        if (e.shiftKey && document.activeElement === first) {
            e.preventDefault();
            last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
            e.preventDefault();
            first.focus();
        }
    };

    docsDrawerToggle.addEventListener('click', (e) => {
        const expanded = docsDrawerToggle.getAttribute('aria-expanded') === 'true';
        if (expanded) closeDrawer(); else openDrawer();
    });
    docsDrawerOverlay.addEventListener('click', closeDrawer);
    if (docsDrawerClose) docsDrawerClose.addEventListener('click', closeDrawer);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { closeDrawer(); } });
    // Close drawer on link click inside (mobile)
    docsDrawer.querySelectorAll('a').forEach(a => a.addEventListener('click', closeDrawer));
}

// Copy code to clipboard
document.querySelectorAll('pre code').forEach(code => {
    const pre = code.parentElement;
    const button = document.createElement('button');
    button.className = 'copy-button';
    button.textContent = 'Copy';
    button.style.cssText = `
        position: absolute;
        top: 8px;
        right: 8px;
        padding: 4px 8px;
        background: var(--primary-color);
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;
        font-size: 0.75rem;
        opacity: 0;
        transition: opacity 0.2s;
    `;
    
    pre.style.position = 'relative';
    pre.appendChild(button);
    
    pre.addEventListener('mouseenter', () => {
        button.style.opacity = '1';
    });
    
    pre.addEventListener('mouseleave', () => {
        button.style.opacity = '0';
    });
    
    button.addEventListener('click', async () => {
        try {
            await navigator.clipboard.writeText(code.textContent);
            button.textContent = 'Copied!';
            setTimeout(() => {
                button.textContent = 'Copy';
            }, 2000);
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    });
});
