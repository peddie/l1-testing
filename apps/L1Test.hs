{-# OPTIONS_GHC -Wall #-}
{-# Language FlexibleContexts #-}
{-# Language ScopedTypeVariables #-}
{-# Language DeriveGeneric #-}
{-# Language DeriveFunctor #-}

module Main
       ( main
       , RoboX(..)
       , SimStates(..)
       , ddtRoboX
       ) where

import GHC.Generics ( Generic, Generic1 )

import System.IO.Unsafe ( unsafePerformIO )

import qualified Numeric.LinearAlgebra.HMatrix as HMat
import Linear

--import Casadi.DMatrix ( DMatrix )
import Casadi.MX ( MX )
import Dyno.Vectorize
import Dyno.View.JV
import Dyno.View.M ( fromHMat )
import Accessors

import L1.L1

data RoboX a =
  RoboX
  { xPos :: a
  , xVel :: a
  } deriving (Functor, Generic, Generic1, Show)
instance Vectorize RoboX
instance Lookup a => Lookup (RoboX a)

--data RoboU a =
--  RoboU
--  { uTorque :: a
--  } deriving (Functor, Generic, Generic1)
--instance Vectorize RoboU

--data RoboTheta a =
--  RoboTheta
--  { qF1 :: a
--  , qF2 :: a
--  } deriving (Functor, Generic, Generic1)
--instance Vectorize RoboTheta

ddtRoboX :: Floating a => FullSystemState RoboX a -> a -> RoboX a
ddtRoboX (FullSystemState x@(RoboX p v) (WQS omegaBar theta sigmaBar)) u  =
--ddtRoboX x@(RoboX p v) u theta sigmaBar omegaBar =
  RoboX
  { xPos = v
  , xVel = (u + m*g*r*(cos p)/2 + sigmaBar + x `dot` theta) * omegaBar
  }
  where
    m = 1
    g = 9.8
    r = 0.5

l1params :: L1Params (JV RoboX) MX
l1params =
  L1Params
  { l1pETheta0 = 0.1
  , l1pOmegaMax = 10
  , l1pSigmaMax = 10
  , l1pThetaMax = 5
  , l1pGamma = 10e3
  , l1pKg = 1
  , l1pP = fromHMat $
           HMat.fromLists
           [ [0.812564928052004, -0.359997120023040]
           , [-0.359997120023040, 0.308568960019748]
           ]
  , l1pW = 1
  }

data SimStates x a =
  SimStates
  { ssX :: x a
  , ssL1 :: L1States x a
  } deriving (Functor, Generic, Generic1, Show)
instance Vectorize x => Vectorize (SimStates x)
instance (Lookup a, Lookup (x a)) => Lookup (SimStates x a)

main :: IO ()
main = do
  lol <- prepareL1 ddtRoboX l1params
  let x0 :: RoboX Double
      x0 = RoboX 1 2

      l0 :: L1States RoboX Double
      l0 =
        L1States
        { l1sXhat = fill 1
        , l1sU = 0
        , l1sWqsHat = fill 0.1
        }
      reference = 0

      wqs0 :: WQS RoboX Double
      wqs0 = fill 0.1

  let dfdt :: WQS RoboX Double -> Double -> SimStates RoboX Double -> SimStates RoboX Double
      dfdt wqs r (SimStates x l1) = unsafePerformIO $ do
        let fss =
              FullSystemState
              { ffsX = x
              , ffsWQS = wqs
              }
        (l1', x') <- lol fss l1 r
        return (SimStates x' l1')

      simTimes = [0,0.01..2]
      sols :: [SimStates RoboX Double]
      sols = integrate' (dfdt wqs0 reference) 0.01 simTimes (SimStates x0 l0)
--  mapM_ print sols
  putStrLn $ unlines $ toMatlab "ret" sols
  putStrLn $ "time = " ++ show simTimes ++ ";"
  return ()


toMatlab :: (Vectorize f, Lookup (f Double)) => String -> [f Double] -> [String]
toMatlab topName xs = map (uncurry (fieldToMatlab xs)) at
  where
    at = flatten $ accessors (fill 0)
    fieldToMatlab xzus name get = topName ++ "." ++ name ++ " = " ++ show (map get xzus) ++ ";"