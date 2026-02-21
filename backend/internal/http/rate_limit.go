package httpapi

import (
	"net"
	"net/http"
	"sync"
	"time"
)

type rateBucket struct {
	windowStart time.Time
	count       int
}

type authRateLimiter struct {
	mu      sync.Mutex
	limit   int
	window  time.Duration
	buckets map[string]rateBucket
}

func newAuthRateLimiter(limit int, window time.Duration) *authRateLimiter {
	return &authRateLimiter{
		limit:   limit,
		window:  window,
		buckets: map[string]rateBucket{},
	}
}

func (r *authRateLimiter) Allow(ip string) bool {
	now := time.Now()
	r.mu.Lock()
	defer r.mu.Unlock()
	bucket, ok := r.buckets[ip]
	if !ok || now.Sub(bucket.windowStart) >= r.window {
		r.buckets[ip] = rateBucket{windowStart: now, count: 1}
		return true
	}
	if bucket.count >= r.limit {
		return false
	}
	bucket.count++
	r.buckets[ip] = bucket
	return true
}

func withAuthRateLimit(next http.Handler, limiter *authRateLimiter) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			host = r.RemoteAddr
		}
		if !limiter.Allow(host) {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}
