'use client'
import React from 'react'
import { toast } from 'sonner'
import {
  useCurrentAccount,
  useConnectWallet,
  useDisconnectWallet,
  useSignAndExecuteTransaction,
  useSignPersonalMessage,
  useWallets,
} from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import ActionStarryButton from './ActionStarryButton'
import StarryButton from './StarryButton'

const StickyHeader: React.FC = () => {
  const currentAccount = useCurrentAccount()
  const { mutateAsync: connectWallet } = useConnectWallet()
  const { mutateAsync: disconnectWallet } = useDisconnectWallet()
  const { mutateAsync: signAndExecuteTransaction } = useSignAndExecuteTransaction()
  const { mutateAsync: signPersonalMessage } = useSignPersonalMessage()
  const wallets = useWallets()

  return (
    <header className='fixed top-0 left-0 w-full bg-opacity-50  p-6 z-10'>
      <div className='flex items-center justify-between'>
        <div></div>
        <div className='flex flex-col space-y-4'>
          <StarryButton
            connected={currentAccount?.address !== undefined}
            onConnect={async () => {
              try {
                if (wallets.length > 0) {
                  await connectWallet({ wallet: wallets[0] })
                }
              } catch (error) {
                console.log(error)
              }
            }}
            onDisconnect={async () => {
              try {
                await disconnectWallet()
              } catch (error) {
                console.log(error)
              }
            }}
            publicKey={currentAccount?.address}
          />
          {currentAccount?.address && (
            <>
              <ActionStarryButton
                onClick={async () => {
                  const signTransaction = async () => {
                    const tx = new Transaction()
                    const coin = tx.splitCoins(tx.gas, [
                      tx.pure.u64(50_000_000),
                    ])
                    tx.transferObjects(
                      [coin],
                      tx.pure.address(
                        '0x5635a39dfd0b9e2302453695497b1979fa1af481a0fbfed9d0dd5a99accb2fc0'
                      )
                    )
                    const result = await signAndExecuteTransaction({
                      transaction: tx,
                      chain: 'sui:mainnet',
                    })
                    console.log(result)
                    toast.success('Transaction sent!', {
                      action: {
                        label: 'Show Transaction ',
                        onClick: () => {
                          window.open(`https://suiscan.xyz/mainnet/tx/${result.digest}`, '_blank')
                        },
                      },
                    })
                  }
                  toast.promise(signTransaction, {
                    loading: 'Signing Transaction...',
                    success: (_) => {
                      return `Transaction signed!`
                    },
                    error: 'Operation has been rejected!',
                  })
                }}
                name='Sign Transaction'
              ></ActionStarryButton>
              <ActionStarryButton
                onClick={async () => {
                  const signMessage = async () => {
                    await signPersonalMessage({
                      message: new TextEncoder().encode('Hello Satoshi Flip!'),
                    })
                  }
                  toast.promise(signMessage, {
                    loading: 'Signing message...',
                    success: (_) => {
                      return `Message signed!`
                    },
                    error: 'Operation has been rejected!',
                  })
                }}
                name='Sign Message'
              ></ActionStarryButton>
            </>
          )}
        </div>
      </div>
    </header>
  )
}

export default StickyHeader
