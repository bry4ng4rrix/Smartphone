'use client'

import React, { Component, ErrorInfo } from 'react'
import { toast } from 'sonner'

interface Props {
  children: React.ReactNode
  /** Custom fallback UI — defaults to null (transparent recovery) */
  fallback?: React.ReactNode
}

interface State {
  hasError: boolean
  error: Error | null
}

/**
 * GlobalErrorBoundary
 * Catches any uncaught React render error below it in the tree,
 * fires a Sonner error toast and optionally renders a fallback UI.
 *
 * Place it in app/layout.tsx just inside <ThemeProvider>.
 */
export class GlobalErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    const message = error?.message ?? 'Erreur inattendue'
    const detail  = info.componentStack?.trim().split('\n')[0] ?? ''

    toast.error(message, {
      description: detail || undefined,
      duration: 8000,
    })

    // Log to console in all envs; swap for Sentry / Datadog in production
    console.error('[GlobalErrorBoundary]', error, info)
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null })
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback

      // Minimal transparent recovery: just unmount the broken tree
      return (
        <div
          role="alert"
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            minHeight: '100dvh',
            gap: '1rem',
            fontFamily: 'system-ui, sans-serif',
            color: '#ef4444',
          }}
        >
          <span style={{ fontSize: '2rem' }}>⚠️</span>
          <p style={{ margin: 0, fontWeight: 600 }}>
            {this.state.error?.message ?? 'Une erreur est survenue'}
          </p>
          <button
            onClick={this.handleRetry}
            style={{
              padding: '0.5rem 1.25rem',
              border: '1px solid #ef4444',
              borderRadius: '0.5rem',
              background: 'transparent',
              color: '#ef4444',
              cursor: 'pointer',
              fontSize: '0.875rem',
            }}
          >
            Réessayer
          </button>
        </div>
      )
    }

    return this.props.children
  }
}
