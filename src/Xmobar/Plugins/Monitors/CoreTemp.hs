-----------------------------------------------------------------------------
-- |
-- Module      :  Plugins.Monitors.CoreTemp
-- Copyright   :  (c) 2019 Felix Springer
--                (c) Juraj Hercek
-- License     :  BSD-style (see LICENSE)
--
-- Maintainer  :  Felix Springer <felixspringer149@gmail.com>
-- Stability   :  unstable
-- Portability :  unportable
--
-- A core temperature monitor for Xmobar
--
-----------------------------------------------------------------------------

module Xmobar.Plugins.Monitors.CoreTemp (startCoreTemp) where

import Xmobar.Plugins.Monitors.Common
import Control.Monad (filterM)
import System.Console.GetOpt
import System.Directory ( doesDirectoryExist
                        , doesFileExist
                        )

-- | Declare Options.
data CTOpts = CTOpts { loadIconPattern :: Maybe IconPattern
                        , mintemp :: Float
                        , maxtemp :: Float
                        }

-- | Set default Options.
defaultOpts :: CTOpts
defaultOpts = CTOpts { loadIconPattern = Nothing
                     , mintemp = 0
                     , maxtemp = 100
                     }

-- | Apply configured Options.
options :: [OptDescr (CTOpts -> CTOpts)]
options = [ Option [] ["load-icon-pattern"]
              (ReqArg
                (\ arg opts -> opts { loadIconPattern = Just $ parseIconPattern arg })
                "")
              ""
          , Option [] ["mintemp"]
              (ReqArg
                (\ arg opts -> opts { mintemp = read arg })
                "")
              ""
          , Option [] ["maxtemp"]
              (ReqArg
                (\ arg opts -> opts { maxtemp = read arg })
                "")
              ""
          ]

-- | Parse Arguments and apply them to Options.
parseOpts :: [String] -> IO CTOpts
parseOpts argv = case getOpt Permute options argv of
                   (opts , _ , []  ) -> return $ foldr id defaultOpts opts
                   (_    , _ , errs) -> ioError . userError $ concat errs

-- | Generate Config with a default template and options.
cTConfig :: IO MConfig
cTConfig = mkMConfig cTTemplate cTOptions
  where cTTemplate = "Temp: <max>°C - <maxpc>%"
        cTOptions = [ "max" , "maxpc" , "maxbar" , "maxvbar" , "maxipat"
                    , "avg" , "avgpc" , "avgbar" , "avgvbar" , "avgipat"
                    ] ++ (map (("core" ++) . show) [0 :: Int ..])

coretempPath :: IO String
coretempPath = do xs <- filterM doesDirectoryExist ps
                  let x = head xs
                  return x
  where ps = [ "/sys/bus/platform/devices/coretemp." ++ (show (x :: Int)) ++ "/" | x <- [0..9] ]

hwmonPath :: IO String
hwmonPath = do p <- coretempPath
               xs <- filterM doesDirectoryExist [ p ++ "hwmon/hwmon" ++ show (x :: Int) ++ "/" | x <- [0..9] ]
               let x = head xs
               return x

corePaths :: IO [String]
corePaths = do p <- hwmonPath
               ls <- filterM doesFileExist [ p ++ "temp" ++ show (x :: Int) ++ "_label" | x <- [0..9] ]
               cls <- filterM isLabelFromCore ls
               return $ map labelToCore cls

isLabelFromCore :: FilePath -> IO Bool
isLabelFromCore p = do a <- readFile p
                       return $ take 4 a == "Core"

labelToCore :: FilePath -> FilePath
labelToCore = (++ "input") . reverse . drop 5 . reverse

cTData :: IO [Float]
cTData = do fps <- corePaths
            fs <- traverse readSingleFile fps
            return fs
  where readSingleFile :: FilePath -> IO Float
        readSingleFile s = do a <- readFile s
                              return $ parseContent a
          where parseContent :: String -> Float
                parseContent = read . head . lines

parseCT :: IO [Float]
parseCT = do rawCTs <- cTData
             let normalizedCTs = map (/ 1000) rawCTs :: [Float]
             return normalizedCTs

formatCT :: CTOpts -> [Float] -> Monitor [String]
formatCT opts cTs = do let CTOpts { mintemp = minT
                                  , maxtemp = maxT } = opts
                           domainT = maxT - minT
                           maxCT = maximum cTs
                           avgCT = sum cTs / (fromIntegral $ length cTs)
                           maxCTPc = (maxCT - minT) / domainT
                           avgCTPc = (avgCT - minT) / domainT

                       cs <- showPercentsWithColors cTs

                       m <- showWithColors (show . (round :: Float -> Int)) maxCT
                       mp <- showWithColors' (show $ (round $ 100*maxCTPc :: Int)) maxCT
                       mb <- showPercentBar maxCT maxCTPc
                       mv <- showVerticalBar maxCT maxCTPc
                       mi <- showIconPattern (loadIconPattern opts) maxCTPc

                       a <- showWithColors (show . (round :: Float -> Int)) avgCT
                       ap <- showWithColors' (show $ (round $ 100*avgCTPc :: Int)) avgCT
                       ab <- showPercentBar avgCT avgCTPc
                       av <- showVerticalBar avgCT avgCTPc
                       ai <- showIconPattern (loadIconPattern opts) avgCTPc

                       let ms = [ m , mp , mb , mv , mi ]
                           as = [ a , ap , ab , av , ai ]

                       return (ms ++ as ++ cs)

runCT :: [String] -> Monitor String
runCT argv = do cTs <- io $ parseCT
                opts <- io $ parseOpts argv
                l <- formatCT opts cTs
                parseTemplate l

startCoreTemp :: [String] -> Int -> (String -> IO ()) -> IO ()
startCoreTemp a = runM a cTConfig runCT
