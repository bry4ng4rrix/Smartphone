'use client'

import { toast } from 'sonner'
import { useCallback } from 'react'

export interface AppError {
  message?: string
  code?: string | number
  details?: string
  hint?: string
}

/**
 * Returns a stable `showError` function that fires a Sonner error toast.
 * Works with API errors, native Errors, and plain strings.
 *
 * Usage:
 *   const { showError } = useErrorToast()
 *   const { error } = await fetch('/api/users')
 *   if (error) showError(error)
 */
export function useErrorToast() {
  const showError = useCallback(
    (error: unknown, fallback = 'Une erreur est survenue') => {
      if (!error) return

      let message = fallback
      let description: string | undefined

      if (typeof error === 'string') {
        message = error
      } else if (error instanceof Error) {
        message = error.message
      } else {
        const e = error as AppError
        message = e.message ?? fallback
        description = e.details ?? e.hint ?? undefined
      }

      toast.error(message, {
        description,
        duration: 5000,
      })
    },
    []
  )

  const showSuccess = useCallback((message: string, description?: string) => {
    toast.success(message, { description, duration: 3000 })
  }, [])

  const showInfo = useCallback((message: string, description?: string) => {
    toast.info(message, { description, duration: 3000 })
  }, [])

  return { showError, showSuccess, showInfo }
}
