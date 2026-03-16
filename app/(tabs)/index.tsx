import { useState } from 'react'
import { Pressable, StyleSheet, Text, View } from 'react-native'
import { supabase } from '../../lib/supabase'

export default function HomeScreen() {
  const [message, setMessage] = useState('Sin probar')

  async function testSupabase() {
    try {
      const { error } = await supabase.auth.getSession()

      if (error) {
        setMessage(`Error: ${error.message}`)
        return
      }

      setMessage('Supabase conectado correctamente')
    } catch (e) {
      setMessage(`Error inesperado: ${e instanceof Error ? e.message : 'desconocido'}`)
    }
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>TU METRO RD AI</Text>
      <Text style={styles.subtitle}>Prueba de conexión con Supabase</Text>

      <Pressable style={styles.button} onPress={testSupabase}>
        <Text style={styles.buttonText}>Probar conexión</Text>
      </Pressable>

      <Text style={styles.result}>{message}</Text>
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0B1220',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    color: '#FFFFFF',
    marginBottom: 12,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#60A5FA',
    marginBottom: 24,
    textAlign: 'center',
  },
  button: {
    backgroundColor: '#2563EB',
    paddingVertical: 14,
    paddingHorizontal: 22,
    borderRadius: 12,
    marginBottom: 20,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '700',
  },
  result: {
    fontSize: 16,
    color: '#CBD5E1',
    textAlign: 'center',
  },
})