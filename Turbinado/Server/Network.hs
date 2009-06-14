module Turbinado.Server.Network (
          receiveHTTPRequest
        , sendHTTPResponse
        , receiveCGIRequest
        , sendCGIResponse
        ) where

import Data.Maybe
import Network.Socket
import Network.FastCGI
import Network.HTTP hiding (receiveHTTP, respondHTTP)
import Network.HTTP.Stream
import Network.StreamSocket
import Network.URI
import qualified System.Environment as Env
import System.IO

import Turbinado.Controller.Monad
import Turbinado.Server.Exception
import Turbinado.Environment.Logger
import Turbinado.Environment.Types
import Turbinado.Environment.Request
import Turbinado.Environment.Response
import Turbinado.Server.StandardResponse
import Turbinado.Utility.Data



-- | Read the request from client.
receiveHTTPRequest :: Socket -> Controller ()
receiveHTTPRequest sock = do
        req <- liftIO $ receiveHTTP sock
        case req of
         Left e -> throwTurbinado $ BadRequest $ "In receiveRequest : " ++ show e
         Right r  -> do e <- get
                        put $ e {Turbinado.Environment.Types.getRequest = Just r}

-- | Get the 'Response' from the 'Environment' and send
-- it back to the client.
sendHTTPResponse :: Socket -> Controller ()
sendHTTPResponse sock = do e <- getEnvironment
                           liftIO $ respondHTTP sock $ fromJust' "Network : sendResponse" $ Turbinado.Environment.Types.getResponse e

-- | Pull a CGI request from stdin
receiveCGIRequest :: URI -> String -> String -> [(String, String)] -> Controller ()
receiveCGIRequest rquri rqmethod rqbody hdrs = 
            do let rqheaders = parseHeaders $ extractHTTPHeaders hdrs
               case rqheaders of
                Left err -> errorResponse $ show err
                Right r  -> do e' <- getEnvironment
                               setEnvironment $ e' {
                                Turbinado.Environment.Types.getRequest = 
                                             Just Request { rqURI = rquri
                                                          , rqMethod = matchRqMethod rqmethod
                                                          , rqHeaders = r
                                                          , rqBody = rqbody
                                                          }
                                }

matchRqMethod :: String -> RequestMethod
matchRqMethod m = fromJust' "Turbinado.Server.Network:matchRqMethod" $
                    lookup m [ ("GET",    GET)
                             , ("POST",   POST)
                             , ("HEAD",   HEAD)
                             , ("PUT"  ,  PUT)
                             , ("DELETE", DELETE)
                             ]

-- | Convert the HTTP.Response to a CGI response for stdout.
sendCGIResponse :: Environment -> CGI CGIResult
sendCGIResponse e = do let r = fromJust' "Network: respondCGI: getResponse failed" $ getResponse e
                           (c1,c2,c3) = rspCode r
                           message = (unlines $ drop 1 $ lines $ show r) ++ "\n\n" ++ rspBody r   -- need to drop the first line from the response for CGI
                       mapM_ (\(Header k v) -> setHeader (show k) v) $ rspHeaders r  
                       setStatus (100*c1+10*c2+c3) (rspReason r)
                       output $ rspBody r

-- | Convert from HTTP_SOME_FLAG to Some-Flag for HTTP.parseHeaders
extractHTTPHeaders :: [(String, String)] -> [String]
extractHTTPHeaders [] = []
extractHTTPHeaders (('H':'T':'T':'P':'_':k,v):hs) = (convertUnderscores k ++ ": " ++ v) : extractHTTPHeaders hs
  where convertUnderscores []       = []
        convertUnderscores ('_':ss) = '-' : convertUnderscores ss
        convertUnderscores (s  :ss) =  s  : convertUnderscores ss
extractHTTPHeaders ((k,v) : hs) = extractHTTPHeaders hs


-- | Lifted from Network.HTTP
rqMethodMap :: [(String, RequestMethod)]
rqMethodMap = [("HEAD",    HEAD),
               ("PUT",     PUT),
               ("GET",     GET),
               ("POST",    POST),
               ("DELETE",  DELETE),
               ("OPTIONS", OPTIONS),
               ("TRACE",   TRACE)]


