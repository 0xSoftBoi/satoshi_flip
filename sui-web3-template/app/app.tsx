'use client'
import { Loader } from '@react-three/drei'
import { Toaster } from 'sonner'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SuiClientProvider, WalletProvider } from '@mysten/dapp-kit'
import { getFullnodeUrl } from '@mysten/sui/client'
import '@mysten/dapp-kit/dist/index.css'
import Background from './components/Background'
import StickyHeader from './components/StickyHeader'
import Torus from './components/Torus/App'
import Socials from './components/Socials'

const queryClient = new QueryClient()
const networks = {
  mainnet: { url: getFullnodeUrl('mainnet') },
  testnet: { url: getFullnodeUrl('testnet') },
  devnet: { url: getFullnodeUrl('devnet') },
}

export default function Home() {
  return (
    <QueryClientProvider client={queryClient}>
      <SuiClientProvider networks={networks} defaultNetwork='mainnet'>
        <WalletProvider autoConnect>
          <Background />
          <StickyHeader />
          <Torus />
          <Toaster position='bottom-left' richColors />
          <Socials />
          <Loader />
        </WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  )
}
