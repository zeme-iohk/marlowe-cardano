{-# LANGUAGE Arrows #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StrictData #-}

module Test.Integration.Marlowe.Local
  ( MarloweRuntime(..)
  , module Test.Integration.Cardano
  , defaultMarloweRuntimeOptions
  , withLocalMarloweRuntime
  , withLocalMarloweRuntime'
  ) where

import Cardano.Api
  ( AsType(..)
  , BabbageEra
  , CardanoEra(..)
  , CardanoMode
  , ChainPoint
  , ConsensusModeParams(..)
  , EpochSlots(..)
  , EraInMode(..)
  , LocalNodeConnectInfo(..)
  , NetworkId(..)
  , NetworkMagic(..)
  , QueryInMode
  , ScriptDataSupportedInEra(ScriptDataInBabbageEra)
  , StakeAddressReference(..)
  , Tx
  , TxBody
  , TxInMode(..)
  , TxValidationErrorInMode
  , deserialiseFromBech32
  , deserialiseFromTextEnvelope
  , getTxId
  , queryNodeLocalState
  , shelleyAddressInEra
  )
import qualified Cardano.Api as Cardano
import qualified Cardano.Api.Byron as Byron
import Cardano.Api.Shelley (AcquiringFailure)
import qualified Cardano.Chain.Genesis as Byron
import Cardano.Chain.UTxO (defaultUTxOConfiguration)
import Cardano.Crypto (abstractHashToBytes)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race_)
import Control.Concurrent.Async.Lifted (Concurrently(..))
import Control.Concurrent.Component
import Control.Concurrent.STM (STM, atomically)
import Control.Exception (SomeException(..), catch, onException, throw, throwIO)
import Control.Monad (when, (<=<))
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (runExceptT)
import Control.Monad.Trans.Reader (runReaderT)
import Control.Monad.Trans.Resource (allocate, runResourceT, unprotect)
import Data.Aeson (eitherDecodeFileStrict)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS
import Data.Either (fromRight)
import Data.Functor (void)
import qualified Data.Map as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Set.NonEmpty as NESet
import Data.String (fromString)
import qualified Data.Text as T
import qualified Data.Text.Lazy.IO as TL
import Data.Time.Clock (secondsToNominalDiffTime)
import Data.UUID.V4 (nextRandom)
import Data.Void (Void)
import Data.Word (Word16)
import Database.PostgreSQL.LibPQ (connectdb, errorMessage, exec, finish, resultErrorMessage)
import Hasql.Connection (settings)
import qualified Hasql.Pool as Pool
import Language.Marlowe.CLI.Transaction (buildPublishingImpl, submitBody)
import Language.Marlowe.CLI.Types
  ( CliEnv(..)
  , MarlowePlutusVersion
  , PrintStats(..)
  , PublishMarloweScripts(..)
  , PublishScript(..)
  , PublishingStrategy(..)
  , ValidatorInfo(..)
  , defaultCoinSelectionStrategy
  )
import Language.Marlowe.Protocol.HeaderSync.Client (MarloweHeaderSyncClient, marloweHeaderSyncClientPeer)
import Language.Marlowe.Protocol.HeaderSync.Server (MarloweHeaderSyncServer, marloweHeaderSyncServerPeer)
import Language.Marlowe.Protocol.HeaderSync.Types (MarloweHeaderSync)
import Language.Marlowe.Protocol.Query.Client (MarloweQueryClient(..), marloweQueryClientPeer)
import Language.Marlowe.Protocol.Query.Server (MarloweQueryServer)
import Language.Marlowe.Protocol.Query.Types (MarloweQuery)
import Language.Marlowe.Protocol.Sync.Client (MarloweSyncClient, marloweSyncClientPeer)
import Language.Marlowe.Protocol.Sync.Server (MarloweSyncServer, marloweSyncServerPeer)
import Language.Marlowe.Protocol.Sync.Types (MarloweSync)
import Language.Marlowe.Runtime.Cardano.Api (fromCardanoAddressInEra, fromCardanoLovelace, fromCardanoTxId)
import Language.Marlowe.Runtime.ChainIndexer
  (ChainIndexerDependencies(..), ChainIndexerSelector, chainIndexer, getChainIndexerSelectorConfig)
import Language.Marlowe.Runtime.ChainIndexer.Database (CommitGenesisBlock(..), DatabaseQueries(..))
import qualified Language.Marlowe.Runtime.ChainIndexer.Database as ChainIndexer
import qualified Language.Marlowe.Runtime.ChainIndexer.Database.PostgreSQL as ChainIndexer
import Language.Marlowe.Runtime.ChainIndexer.Genesis (GenesisBlock, computeGenesisBlock)
import Language.Marlowe.Runtime.ChainIndexer.NodeClient (CostModel(CostModel))
import Language.Marlowe.Runtime.ChainSync (ChainSyncDependencies(..), chainSync)
import Language.Marlowe.Runtime.ChainSync.Api
  ( Assets(..)
  , ChainSyncCommand
  , ChainSyncQuery(..)
  , RuntimeChainSeek
  , RuntimeChainSeekClient
  , RuntimeChainSeekServer
  , TransactionOutput(..)
  , TxOutRef(TxOutRef)
  , WithGenesis(..)
  , fromCardanoScriptHash
  )
import qualified Language.Marlowe.Runtime.ChainSync.Database as ChainSync
import qualified Language.Marlowe.Runtime.ChainSync.Database.PostgreSQL as ChainSync
import Language.Marlowe.Runtime.Core.Api (MarloweVersion(..))
import Language.Marlowe.Runtime.Core.ScriptRegistry (MarloweScripts(..), ReferenceScriptUtxo(..))
import qualified Language.Marlowe.Runtime.Core.ScriptRegistry as ScriptRegistry
import Language.Marlowe.Runtime.Indexer
  (MarloweIndexerDependencies(..), MarloweIndexerSelector, getMarloweIndexerSelectorConfig, marloweIndexer)
import qualified Language.Marlowe.Runtime.Indexer.Database as Indexer
import qualified Language.Marlowe.Runtime.Indexer.Database.PostgreSQL as Indexer
import Language.Marlowe.Runtime.Sync (SyncDependencies(..), sync)
import qualified Language.Marlowe.Runtime.Sync.Database as Sync
import qualified Language.Marlowe.Runtime.Sync.Database.PostgreSQL as Sync
import Language.Marlowe.Runtime.Transaction
import Language.Marlowe.Runtime.Transaction.Api (MarloweTxCommand)
import Language.Marlowe.Runtime.Transaction.Query (LoadMarloweContext)
import qualified Language.Marlowe.Runtime.Transaction.Query as Query
import Language.Marlowe.Runtime.Transaction.Server (TransactionServerSelector)
import Language.Marlowe.Runtime.Transaction.Submit (SubmitJob, SubmitJobDependencies(..))
import qualified Language.Marlowe.Runtime.Transaction.Submit as Submit
import Language.Marlowe.Runtime.Web.Server (ServerDependencies(..), server)
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.Protocol.ChainSeek.Client (chainSeekClientPeer)
import Network.Protocol.ChainSeek.Server (chainSeekServerPeer)
import Network.Protocol.Driver
import qualified Network.Protocol.Driver as Driver
import Network.Protocol.Handshake.Server (handshakeClientServerPair, handshakeConnectionSource)
import Network.Protocol.Handshake.Types (Handshake)
import Network.Protocol.Job.Client (JobClient, jobClientPeer)
import Network.Protocol.Job.Server (JobServer, jobServerPeer)
import Network.Protocol.Job.Types (Job)
import Network.Protocol.Query.Client (QueryClient, liftQuery, queryClientPeer)
import Network.Protocol.Query.Server (QueryServer, queryServerPeer)
import Network.Protocol.Query.Types (Query)
import Network.Wai.Handler.Warp (run)
import Observe.Event (EventBackend, narrowEventBackend)
import Observe.Event.Backend (newOnceFlagMVar, noopEventBackend)
import Observe.Event.Component
  (ConfigWatcherSelector(..), LoggerDependencies(..), SelectorConfig(..), logger, prependKey, singletonFieldConfig)
import Ouroboros.Network.Protocol.LocalTxSubmission.Type (SubmitResult)
import Servant.Client (BaseUrl(..), ClientError, ClientM, Scheme(..), mkClientEnv, runClientM)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.IO (BufferMode(..), IOMode(..), hSetBuffering)
import System.Process (readCreateProcessWithExitCode)
import qualified System.Process as SP
import System.Random (randomRIO)
import Test.Integration.Cardano
import qualified Test.Integration.Cardano as SpoNode (SpoNode(..))
import Text.Read (readMaybe)
import UnliftIO (MonadUnliftIO, withRunInIO)

data MarloweRuntime = MarloweRuntime
  { marloweHeaderSyncConnector :: SomeClientConnector MarloweHeaderSyncClient IO
  , marloweSyncConnector :: SomeClientConnector MarloweSyncClient IO
  , marloweQueryConnector :: SomeClientConnector MarloweQueryClient IO
  , txJobConnector :: SomeClientConnector (JobClient MarloweTxCommand) IO
  , marloweHeaderSyncPort :: Int
  , marloweSyncPort :: Int
  , marloweQueryPort :: Int
  , txJobPort :: Int
  , runWebClient :: forall a. ClientM a -> IO (Either ClientError a)
  , marloweScripts :: MarloweScripts
  , testnet :: LocalTestnet
  }

data MarloweRuntimeOptions = MarloweRuntimeOptions
  { databaseHost :: ByteString
  , databasePort :: Word16
  , databaseUser :: ByteString
  , databasePassword :: ByteString
  , tempDatabase :: ByteString
  , cleanup :: Bool
  , localTestnetOptions :: LocalTestnetOptions
  }

defaultMarloweRuntimeOptions :: IO MarloweRuntimeOptions
defaultMarloweRuntimeOptions = do
  databaseHost <- lookupEnv "MARLOWE_RT_TEST_DB_HOST"
  databasePort <- lookupEnv "MARLOWE_RT_TEST_DB_PORT"
  databaseUser <- lookupEnv "MARLOWE_RT_TEST_DB_USER"
  databasePassword <- lookupEnv "MARLOWE_RT_TEST_DB_PASSWORD"
  tempDatabase <- lookupEnv "MARLOWE_RT_TEST_TEMP_DB"
  cleanupDatabase <- lookupEnv "MARLOWE_RT_TEST_CLEANUP_DATABASE"
  pure $ MarloweRuntimeOptions
    (maybe "127.0.0.1" fromString databaseHost)
    (fromMaybe 5432 $ readMaybe =<< databasePort)
    (maybe "postgres" fromString databaseUser)
    (maybe "" fromString databasePassword)
    (maybe "template1" fromString tempDatabase)
    (fromMaybe True $ readMaybe =<< cleanupDatabase)
    defaultOptions

withLocalMarloweRuntime :: MonadUnliftIO m => (MarloweRuntime -> m ()) -> m ()
withLocalMarloweRuntime test = do
  options <- liftIO defaultMarloweRuntimeOptions
  withLocalMarloweRuntime' options test

withLocalMarloweRuntime' :: MonadUnliftIO m => MarloweRuntimeOptions -> (MarloweRuntime -> m ()) -> m ()
withLocalMarloweRuntime' MarloweRuntimeOptions{..} test = withRunInIO \runInIO ->
  withLocalTestnet' localTestnetOptions \testnet@LocalTestnet{..} -> runResourceT do
    let localConsensusModeParams = CardanoModeParams $ EpochSlots 500
    let localNodeNetworkId = Testnet $ NetworkMagic $ fromIntegral testnetMagic
    let localNodeSocketPath = SpoNode.socket . head $ spoNodes
    let localNodeConnectInfo = LocalNodeConnectInfo{..}
    marloweScripts <- liftIO $ publishCurrentScripts testnet localNodeConnectInfo
    (dbReleaseKey, dbName) <- allocate (createDatabase workspace) (cleanupDatabase 10_000)
    liftIO $ migrateDatabase dbName
    let connectionString = settings databaseHost databasePort databaseUser databasePassword dbName
    let acquirePool = Pool.acquire (100, secondsToNominalDiffTime 5, connectionString)
    (_, pool) <- allocate acquirePool Pool.release
    logFileHandle <- openWorkspaceFile workspace "logs/runtime.log" WriteMode
    liftIO $ hSetBuffering logFileHandle LineBuffering
    (Concurrently runLogger, rootEventBackend) <- liftIO $ atomically $ unComponent logger LoggerDependencies
      { configFilePath = Just $ resolveWorkspacePath workspace "runtime.log.config"
      , getSelectorConfig = getRuntimeSelectorConfig
      , newRef = nextRandom
      , newOnceFlag = newOnceFlagMVar
      , writeText = TL.hPutStrLn logFileHandle
      , injectConfigWatcherSelector = ConfigWatcher
      }
    Channels{..} <- liftIO $ atomically $ setupChannels rootEventBackend
    genesisConfigResult <- runExceptT . Byron.readGenesisData $ byronGenesisJson network
    (genesisData, genesisHash) <- case genesisConfigResult of
      Left e -> fail $ show e
      Right a -> pure a
    shelleyGenesisConfig <- liftIO $ either error id <$> eitherDecodeFileStrict (shelleyGenesisJson network)
    let
      byronGenesisConfig = Byron.Config
        genesisData
        genesisHash
        (Byron.toByronRequiresNetworkMagic localNodeNetworkId)
        defaultUTxOConfiguration

      genesisBlock = computeGenesisBlock
        (abstractHashToBytes $ Byron.unGenesisHash genesisHash)
        byronGenesisConfig
        shelleyGenesisConfig

      chainIndexerDatabaseQueries = ChainIndexer.hoistDatabaseQueries
        (either (fail . show) pure <=< Pool.use pool)
        (ChainIndexer.databaseQueries genesisBlock)

      chainSeekDatabaseQueries = ChainSync.hoistDatabaseQueries
        (either (fail . show) pure <=< Pool.use pool)
        (ChainSync.databaseQueries localNodeNetworkId)

      marloweIndexerDatabaseQueries = Indexer.hoistDatabaseQueries
        (either (fail . show) pure <=< Pool.use pool)
        (Indexer.databaseQueries securityParameter)

      marloweSyncDatabaseQueries eventBackend = Sync.logDatabaseQueries eventBackend $ Sync.hoistDatabaseQueries
        (either (fail . show) pure <=< Pool.use pool)
        Sync.databaseQueries

    webPort <- liftIO $ randomRIO (4000, 5000)
    marloweHeaderSyncPort <- liftIO $ randomRIO (5000, 6000)
    let marloweSyncPort = marloweHeaderSyncPort + 1
    let marloweQueryPort = marloweHeaderSyncPort + 2
    let txJobPort = marloweHeaderSyncPort + 3
    manager <- liftIO $ newManager defaultManagerSettings

    let submitConfirmationBlocks = 2
    let chainSyncConnector = SomeConnector $ clientConnector chainSyncPair
    let chainSyncJobConnector = SomeConnector $ clientConnector chainSyncJobPair
    let mkSubmitJob = Submit.mkSubmitJob SubmitJobDependencies{..}
    let baseUrl = BaseUrl Http "localhost" webPort ""
    let clientEnv = mkClientEnv manager baseUrl
    let
      runWebClient :: ClientM a -> IO (Either ClientError a)
      runWebClient = flip runClientM clientEnv

    let marloweSyncConnector = SomeConnector $ clientConnector marloweSyncPair
    let marloweHeaderSyncConnector = SomeConnector $ clientConnector marloweHeaderSyncPair
    let marloweQueryConnector = SomeConnector $ clientConnector marloweQueryPair
    let txJobConnector = SomeConnector $ clientConnector txJobPair

    -- Persist the genesis block before starting the services so that they
    -- exist already and no database queries fail.
    liftIO do
      runCommitGenesisBlock (commitGenesisBlock chainIndexerDatabaseQueries) genesisBlock
      onException
        ( runComponent_ runtime RuntimeDependencies{..}
          `race_` runLogger
          `race_` runInIO (test MarloweRuntime{..})
        )
        (unprotect dbReleaseKey)
  where
    rootConnectionString = settings databaseHost databasePort databaseUser databasePassword tempDatabase

    checkResult connection = \case
      Nothing -> do
        msg <- errorMessage connection
        fail $ "Fatal database error: " <> show msg
      Just r -> do
        resultErrorMessage r >>= \case
          Nothing -> pure ()
          Just "" -> pure ()
          Just msg -> fail $ "Error creating database: " <> show msg

    createDatabase workspace = do
      connection <- connectdb rootConnectionString
      let dbName = fromString $ "chain_test_" <> show (workspaceId workspace)
      result1 <- exec connection $ "CREATE DATABASE \"" <> dbName <> "\"" <> ";"
      result2 <- exec connection $ "GRANT ALL PRIVILEGES ON DATABASE \"" <> dbName <> "\" TO " <> databaseUser <> ";"
      checkResult connection result1
      checkResult connection result2
      finish connection
      pure dbName

    cleanupDatabase retryDelay dbName = when cleanup do
      catch
        ( do
          connection <- connectdb rootConnectionString
          result <- exec connection $ "DROP DATABASE \"" <> dbName <> "\";"
          checkResult connection result
          finish connection
        )
        ( \(SomeException e) -> if retryDelay > 1_000_000
            then throw e
            else do
              threadDelay retryDelay
              cleanupDatabase (retryDelay * 10) dbName
        )

    migrateDatabase dbName = do
      (exitCode, _, stderr) <- flip readCreateProcessWithExitCode "" $ (SP.proc "sqitch"
        [ "deploy"
        , "-h", BS.unpack databaseHost
        , "-p", show databasePort
        , "-u", BS.unpack databaseUser
        , "-d", BS.unpack dbName
        ])
        { SP.cwd = Just "./marlowe-chain-sync"
        }
      case exitCode of
        ExitFailure _ -> fail $ "chain sqitch failed: \n" <> stderr
        ExitSuccess -> do
          (exitCode', _, stderr') <- flip readCreateProcessWithExitCode "" $ (SP.proc "sqitch"
            [ "deploy"
            , "-h", BS.unpack databaseHost
            , "-p", show databasePort
            , "-u", BS.unpack databaseUser
            , "-d", BS.unpack dbName
            ])
            { SP.cwd = Just "./marlowe-runtime/marlowe-indexer"
            }
          case exitCode' of
            ExitFailure _ -> fail $ "marlowe sqitch failed: \n" <> stderr'
            ExitSuccess -> pure ()

publishCurrentScripts :: LocalTestnet -> LocalNodeConnectInfo CardanoMode -> IO MarloweScripts
publishCurrentScripts LocalTestnet{..} localNodeConnectInfo = do
  let Delegator{..} = head delegators
  let PaymentKeyPair{..} = paymentKeyPair
  let StakingKeyPair{..} = stakingKeyPair
  signingKey <- Left
      . either (error . show) id
      . deserialiseFromTextEnvelope (AsSigningKey AsPaymentKey)
      . either error id
    <$> eitherDecodeFileStrict paymentSKey
  changeAddress <-
    either (error . show) shelleyAddressInEra
        . deserialiseFromBech32 (AsAddress AsShelleyAddr)
        . T.pack
      <$> execCli
        [ "address", "build"
        , "--payment-verification-key-file", paymentVKey
        , "--stake-verification-key-file", stakingVKey
        , "--testnet-magic", show testnetMagic
        ]
  let publishingStrategy = PublishPermanently NoStakeAddress
  let coinSelectionStrategy = defaultCoinSelectionStrategy
  either throwIO pure =<< runExceptT do
    flip runReaderT (CliEnv ScriptDataInBabbageEra) do
      (txBody, publishScripts) <- buildPublishingImpl
        localNodeConnectInfo
        signingKey
        Nothing
        changeAddress
        publishingStrategy
        coinSelectionStrategy
        (PrintStats False)
      void $ submitBody localNodeConnectInfo txBody [signingKey] 30
      pure $ toMarloweScripts testnetMagic txBody publishScripts

toMarloweScripts :: Int -> TxBody BabbageEra -> PublishMarloweScripts MarlowePlutusVersion BabbageEra -> MarloweScripts
toMarloweScripts testnetMagic txBody PublishMarloweScripts{..} = MarloweScripts{..}
  where
    marloweValidatorInfo = psReferenceValidator pmsMarloweScript
    payoutValidatorInfo = psReferenceValidator pmsRolePayoutScript
    marloweScript = fromCardanoScriptHash $ viHash marloweValidatorInfo
    payoutScript = fromCardanoScriptHash $ viHash payoutValidatorInfo
    networkId = Testnet $ NetworkMagic $ fromIntegral testnetMagic
    publishTxId = fromCardanoTxId $ getTxId txBody
    marloweTxOutRef = TxOutRef publishTxId 1
    payoutTxOutRef = TxOutRef publishTxId 2
    marloweReferenceScriptUTxO = ReferenceScriptUtxo
      { txOutRef = marloweTxOutRef
      , txOut = TransactionOutput
        { address = fromCardanoAddressInEra BabbageEra $ psPublisher pmsMarloweScript
        , assets = Assets (fromCardanoLovelace $ psMinAda pmsMarloweScript) mempty
        , datumHash = Nothing
        , datum = Nothing
        }
      , script = viScript marloweValidatorInfo
      }
    payoutReferenceScriptUTxO = ReferenceScriptUtxo
      { txOutRef = payoutTxOutRef
      , txOut = TransactionOutput
        { address = fromCardanoAddressInEra BabbageEra $ psPublisher pmsRolePayoutScript
        , assets = Assets (fromCardanoLovelace $ psMinAda pmsRolePayoutScript) mempty
        , datumHash = Nothing
        , datum = Nothing
        }
      , script = viScript payoutValidatorInfo
      }
    marloweScriptUTxOs = Map.singleton networkId marloweReferenceScriptUTxO
    payoutScriptUTxOs = Map.singleton networkId payoutReferenceScriptUTxO

data RuntimeSelector f where
  ChainSeekPair :: ClientServerPairSelector (Handshake RuntimeChainSeek) f -> RuntimeSelector f
  ChainSyncJobPair :: ClientServerPairSelector (Handshake (Job ChainSyncCommand)) f -> RuntimeSelector f
  ChainSyncQueryPair :: ClientServerPairSelector (Handshake (Query ChainSyncQuery)) f -> RuntimeSelector f
  HeaderSyncPair :: ClientServerPairSelector (Handshake MarloweHeaderSync) f -> RuntimeSelector f
  MarloweSyncPair :: ClientServerPairSelector (Handshake MarloweSync) f -> RuntimeSelector f
  MarloweQueryPair :: ClientServerPairSelector (Handshake MarloweQuery) f -> RuntimeSelector f
  TxJobPair :: ClientServerPairSelector (Handshake (Job MarloweTxCommand)) f -> RuntimeSelector f
  HeaderSyncTCP :: ConnectorSelector (Handshake MarloweHeaderSync) f -> RuntimeSelector f
  MarloweSyncTCP :: ConnectorSelector (Handshake MarloweSync) f -> RuntimeSelector f
  MarloweQueryTCP :: ConnectorSelector (Handshake MarloweQuery) f -> RuntimeSelector f
  TxJobTCP :: ConnectorSelector (Handshake (Job MarloweTxCommand)) f -> RuntimeSelector f
  TxEvent :: TransactionServerSelector f -> RuntimeSelector f
  ChainIndexerEvent :: ChainIndexerSelector f -> RuntimeSelector f
  MarloweIndexerEvent :: MarloweIndexerSelector f -> RuntimeSelector f
  ConfigWatcher :: ConfigWatcherSelector f -> RuntimeSelector f
  SyncDatabaseEvent :: Sync.DatabaseSelector f -> RuntimeSelector f

data RuntimeDependencies r = RuntimeDependencies
  { chainSyncPair :: ClientServerPair (Handshake RuntimeChainSeek) RuntimeChainSeekServer RuntimeChainSeekClient IO
  , chainSyncJobPair :: ClientServerPair (Handshake (Job ChainSyncCommand)) (JobServer ChainSyncCommand) (JobClient ChainSyncCommand) IO
  , chainSyncQueryPair :: ClientServerPair (Handshake (Query ChainSyncQuery)) (QueryServer ChainSyncQuery) (QueryClient ChainSyncQuery) IO
  , marloweHeaderSyncPair :: ClientServerPair (Handshake MarloweHeaderSync) MarloweHeaderSyncServer MarloweHeaderSyncClient IO
  , marloweSyncPair :: ClientServerPair (Handshake MarloweSync) MarloweSyncServer MarloweSyncClient IO
  , marloweQueryPair :: ClientServerPair (Handshake MarloweQuery) MarloweQueryServer MarloweQueryClient IO
  , txJobPair :: ClientServerPair (Handshake (Job MarloweTxCommand)) (JobServer MarloweTxCommand) (JobClient MarloweTxCommand) IO
  , chainIndexerDatabaseQueries :: ChainIndexer.DatabaseQueries IO
  , chainSeekDatabaseQueries :: ChainSync.DatabaseQueries IO
  , genesisBlock :: !GenesisBlock
  , localNodeConnectInfo :: LocalNodeConnectInfo CardanoMode
  , marloweIndexerDatabaseQueries :: Indexer.DatabaseQueries IO
  , marloweSyncDatabaseQueries :: EventBackend IO r Sync.DatabaseSelector -> Sync.DatabaseQueries IO
  , mkSubmitJob :: Tx BabbageEra -> STM SubmitJob
  , rootEventBackend :: EventBackend IO r RuntimeSelector
  , securityParameter :: Int
  , marloweScripts :: MarloweScripts
  , webPort :: Int
  , marloweHeaderSyncPort :: Int
  , marloweSyncPort :: Int
  , marloweQueryPort :: Int
  , txJobPort :: Int
  }

runtime :: Component IO (RuntimeDependencies r) ()
runtime = proc RuntimeDependencies{..} -> do
  let
    getScripts :: MarloweVersion v -> Set MarloweScripts
    getScripts MarloweV1 = Set.singleton marloweScripts

    getCurrentScripts :: MarloweVersion v -> MarloweScripts
    getCurrentScripts MarloweV1 = marloweScripts

    LocalNodeConnectInfo{..} = localNodeConnectInfo

  headerSyncSource <- handshakeConnectionSource <$> tcpServer -< TcpServerDependencies "127.0.0.1" (fromIntegral marloweHeaderSyncPort) marloweHeaderSyncServerPeer
  syncSource <- handshakeConnectionSource <$> tcpServer -< TcpServerDependencies "127.0.0.1" (fromIntegral marloweSyncPort) marloweSyncServerPeer
  querySource <- handshakeConnectionSource <$> tcpServer -< TcpServerDependencies "127.0.0.1" (fromIntegral marloweQueryPort) id
  txJobSource <- handshakeConnectionSource <$> tcpServer -< TcpServerDependencies "127.0.0.1" (fromIntegral txJobPort) jobServerPeer

  chainIndexer -<
    let
      maxCost = 100_000
      costModel = CostModel 1 10
      persistRateLimit = secondsToNominalDiffTime 0.1
      databaseQueries = chainIndexerDatabaseQueries
      eventBackend = narrowEventBackend ChainIndexerEvent rootEventBackend
      connectToLocalNode = Cardano.connectToLocalNode localNodeConnectInfo
     in
      ChainIndexerDependencies{..}

  marloweIndexer -< MarloweIndexerDependencies
    { databaseQueries = marloweIndexerDatabaseQueries
    , eventBackend = narrowEventBackend MarloweIndexerEvent rootEventBackend
    , chainSyncConnector = SomeConnector $ clientConnector chainSyncPair
    , chainSyncQueryConnector = SomeConnector $ clientConnector chainSyncQueryPair
    , pollingInterval = secondsToNominalDiffTime 0.01
    , marloweScriptHashes = NESet.singleton $ ScriptRegistry.marloweScript marloweScripts
    , payoutScriptHashes = NESet.singleton $ ScriptRegistry.payoutScript marloweScripts
    }

  sync -< SyncDependencies
    { databaseQueries = marloweSyncDatabaseQueries $ narrowEventBackend SyncDatabaseEvent rootEventBackend
    , syncSource = SomeConnectionSource $ mergeConnectionSource (logConnectionSource (narrowEventBackend MarloweSyncTCP rootEventBackend) syncSource) $ Driver.connectionSource marloweSyncPair
    , headerSyncSource = SomeConnectionSource $ mergeConnectionSource (logConnectionSource (narrowEventBackend HeaderSyncTCP rootEventBackend) headerSyncSource) $ Driver.connectionSource marloweHeaderSyncPair
    , querySource = SomeConnectionSource $ mergeConnectionSource (logConnectionSource (narrowEventBackend MarloweQueryTCP rootEventBackend) querySource) $ Driver.connectionSource marloweQueryPair
    }

  chainSync -<
    let
      databaseQueries = chainSeekDatabaseQueries

      queryLocalNodeState :: Maybe ChainPoint -> QueryInMode CardanoMode result -> IO (Either AcquiringFailure result)
      queryLocalNodeState = queryNodeLocalState localNodeConnectInfo

      submitTxToNodeLocal :: CardanoEra era -> Tx era -> IO (SubmitResult (TxValidationErrorInMode CardanoMode))
      submitTxToNodeLocal era tx = Cardano.submitTxToNodeLocal localNodeConnectInfo $ TxInMode tx case era of
        ByronEra -> ByronEraInCardanoMode
        ShelleyEra -> ShelleyEraInCardanoMode
        AllegraEra -> AllegraEraInCardanoMode
        MaryEra -> MaryEraInCardanoMode
        AlonzoEra -> AlonzoEraInCardanoMode
        BabbageEra -> BabbageEraInCardanoMode
     in
      ChainSyncDependencies
        { syncSource = SomeConnectionSource $ Driver.connectionSource chainSyncPair
        , querySource = SomeConnectionSource $ Driver.connectionSource chainSyncQueryPair
        , jobSource = SomeConnectionSource $ Driver.connectionSource chainSyncJobPair
        , ..
        }

  transaction -<
    let
      queryChainSync :: ChainSyncQuery Void err results -> IO results
      queryChainSync = fmap (fromRight $ error "failed to query chain sync server")
        . runConnector (clientConnector chainSyncQueryPair)
        . liftQuery

      loadWalletContext = Query.loadWalletContext $ queryChainSync . GetUTxOs

      networkId = localNodeNetworkId

      loadMarloweContext :: LoadMarloweContext r
      loadMarloweContext = Query.loadMarloweContext
        getScripts
        networkId
        (SomeConnector $ clientConnector chainSyncPair)
        (SomeConnector $ clientConnector chainSyncQueryPair)

      eventBackend = narrowEventBackend TxEvent rootEventBackend
    in
      TransactionDependencies
        { chainSyncConnector = SomeConnector $ clientConnector chainSyncPair
        , connectionSource = SomeConnectionSource $ mergeConnectionSource (logConnectionSource (narrowEventBackend TxJobTCP rootEventBackend) txJobSource) $ Driver.connectionSource txJobPair
        , ..
        }

  server -< ServerDependencies
    { openAPIEnabled = False
    , accessControlAllowOriginAll = False
    , runApplication = run webPort
    , marloweQueryConnector = SomeConnector $ clientConnector marloweQueryPair
    , txJobConnector = SomeConnector $ clientConnector txJobPair
    , eventBackend = noopEventBackend ()
    }

data Channels = Channels
  { chainSyncPair :: ClientServerPair (Handshake RuntimeChainSeek) RuntimeChainSeekServer RuntimeChainSeekClient IO
  , chainSyncJobPair :: ClientServerPair (Handshake (Job ChainSyncCommand)) (JobServer ChainSyncCommand) (JobClient ChainSyncCommand) IO
  , chainSyncQueryPair :: ClientServerPair (Handshake (Query ChainSyncQuery)) (QueryServer ChainSyncQuery) (QueryClient ChainSyncQuery) IO
  , marloweHeaderSyncPair :: ClientServerPair (Handshake MarloweHeaderSync) MarloweHeaderSyncServer MarloweHeaderSyncClient IO
  , marloweSyncPair :: ClientServerPair (Handshake MarloweSync) MarloweSyncServer MarloweSyncClient IO
  , marloweQueryPair :: ClientServerPair (Handshake MarloweQuery) MarloweQueryServer MarloweQueryClient IO
  , txJobPair :: ClientServerPair (Handshake (Job MarloweTxCommand)) (JobServer MarloweTxCommand) (JobClient MarloweTxCommand) IO
  }

setupChannels :: EventBackend IO r RuntimeSelector -> STM Channels
setupChannels eventBackend = do
  chainSyncPair <- logClientServerPair (narrowEventBackend ChainSeekPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    (chainSeekServerPeer Genesis)
    (chainSeekClientPeer Genesis)
  chainSyncJobPair <- logClientServerPair (narrowEventBackend ChainSyncJobPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    jobServerPeer
    jobClientPeer
  chainSyncQueryPair <- logClientServerPair (narrowEventBackend ChainSyncQueryPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    queryServerPeer
    queryClientPeer
  marloweHeaderSyncPair <- logClientServerPair (narrowEventBackend HeaderSyncPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    marloweHeaderSyncServerPeer
    marloweHeaderSyncClientPeer
  marloweSyncPair <- logClientServerPair (narrowEventBackend MarloweSyncPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    marloweSyncServerPeer
    marloweSyncClientPeer
  marloweQueryPair <- logClientServerPair (narrowEventBackend MarloweQueryPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    id
    marloweQueryClientPeer
  txJobPair <- logClientServerPair (narrowEventBackend TxJobPair eventBackend) . handshakeClientServerPair <$> clientServerPair
    jobServerPeer
    jobClientPeer
  pure Channels{..}

getRuntimeSelectorConfig :: RuntimeSelector f -> SelectorConfig f
getRuntimeSelectorConfig = \case
  ChainSeekPair sel -> prependKey "chain-sync" $ getClientServerPairSelectorConfig True True sel
  ChainSyncJobPair sel -> prependKey "chain-sync-job" $ getClientServerPairSelectorConfig True True sel
  ChainSyncQueryPair sel -> prependKey "chain-sync-query" $ getClientServerPairSelectorConfig True True sel
  HeaderSyncPair sel -> prependKey "header-sync" $ getClientServerPairSelectorConfig True True sel
  MarloweSyncPair sel -> prependKey "marlowe-sync" $ getClientServerPairSelectorConfig True True sel
  MarloweQueryPair sel -> prependKey "marlowe-query" $ getClientServerPairSelectorConfig True True sel
  TxJobPair sel -> prependKey "tx-job" $ getClientServerPairSelectorConfig True True sel
  HeaderSyncTCP sel -> prependKey "header-sync.tcp" $ getConnectorSelectorConfig True True sel
  MarloweSyncTCP sel -> prependKey "marlowe-sync.tcp" $ getConnectorSelectorConfig True True sel
  MarloweQueryTCP sel -> prependKey "marlowe-query.tcp" $ getConnectorSelectorConfig True True sel
  TxJobTCP sel -> prependKey "tx-job.tcp" $ getConnectorSelectorConfig True True sel
  TxEvent sel -> prependKey "marlowe-tx" $ getTransactionSererSelectorConfig sel
  ChainIndexerEvent sel -> prependKey "marlowe-chain-indexer" $ getChainIndexerSelectorConfig sel
  MarloweIndexerEvent sel -> prependKey "marlowe-indexer" $ getMarloweIndexerSelectorConfig sel
  SyncDatabaseEvent sel -> prependKey "marlowe-sync-database" $ Sync.getDatabaseSelectorConfig sel
  ConfigWatcher ReloadConfig -> SelectorConfig "reload-log-config" True
    $ singletonFieldConfig "config" True
