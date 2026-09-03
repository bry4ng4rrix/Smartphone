'use client'

import { useEffect, useState } from 'react'
import { djangoClient } from '@/lib/django-client'
import { User } from '@/lib/types'

export function useAuth() {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const initAuth = async () => {
      try {
        if (djangoClient.isAuthenticated()) {
          const currentUser = await djangoClient.auth.getCurrentUser()
          setUser(currentUser)
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load user')
        setUser(null)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [])

  const login = async (email: string, password: string) => {
    setIsLoading(true)
    setError(null)
    try {
      const response = await djangoClient.auth.login(email, password)
      setUser(response.user as any)
      return response
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Login failed'
      setError(errorMessage)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const register = async (
    email: string,
    username: string,
    password: string,
    role: string,
  ) => {
    setIsLoading(true)
    setError(null)
    try {
      const response = await djangoClient.auth.register(email, username, password, role)
      setUser(response.user)
      return response
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Registration failed'
      setError(errorMessage)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const logout = () => {
    djangoClient.auth.logout()
    setUser(null)
    setError(null)
  }

  const isAuthenticated = !!user && user.is_approved
  const isPendingApproval = !!user && !user.is_approved

  return {
    user,
    isAuthenticated,
    isPendingApproval,
    isLoading,
    error,
    login,
    register,
    logout,
  }
}
