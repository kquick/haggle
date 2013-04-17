{-# LANGUAGE KindSignatures, TypeFamilies #-}
-- | Haggle is a Haskell graph library.
--
-- The main idea behind haggle is that graphs are constructed with mutation
-- (either in 'IO' or 'ST').  After the graph is constructed, it is frozen
-- into an immutable graph.  This split is a major difference between
-- haggle and the other major Haskell graph library, fgl, which is
-- formulated in terms of inductive graphs that can always be modified
-- in a purely-functional way.  Supporting the inductive graph interface
-- severely limits implementation choices and optimization opportunities, so
-- haggle tries a different approach.
--
-- Furthermore, the types of vertices (nodes in FGL) and edges are held
-- as abstract in haggle, allowing for changes later if necessary.  That said,
-- changes are unlikely and the representations are exposed (with no
-- guarantees) through an Internal module.
--
-- Enough talk, example time:
--
-- > import Control.Monad ( replicateM )
-- > import Data.Graph.Haggle
-- > import Data.Graph.Haggle.Digraph
-- > import Data.Graph.Haggle.Algorithms.DFS
-- >
-- > main :: IO ()
-- > main = do
-- >   g <- newMDigraph
-- >   [v0, v1, v2] <- replicateM 3 (addVertex g)
-- >   e1 <- addEdge g v0 v1
-- >   e2 <- addEdge g v1 v2
-- >   gi <- freeze g
-- >   print (dfs gi v1) -- [V 1, V 2] since the first vertex is 0
--
-- The example builds a graph with three vertices and performs a DFS
-- from the middle vertex.  Note that the DFS algorithm is implemented on
-- immutable graphs, so we freeze the mutable graph before traversing it.  The
-- graph type in this example is a directed graph.
--
-- There are other graph variants that support efficient access to predecessor
-- edges: bidirectional graphs.  There are also simple graph variants that
-- prohibit parallel edges.
--
-- The core graph implementations support only vertices and edges.  /Adapters/
-- add support for 'Vertex' and 'Edge' labels.  See 'EdgeLabelAdapter',
-- 'VertexLabelAdapter', and 'LabelAdapter' (which supports both).  This
-- split allows the core implementations of graphs and graph algorithms to
-- be fast and compact (since they do not need to allocate storage for or
-- manipulate labels).  The adapters store labels on the side, similarly
-- to the property maps of Boost Graph Library.  Also note that the adapters
-- are strongly typed.  To add edges to a graph with edge labels, you must call
-- 'addLabeledEdge' instead of 'addEdge'.  Likewise for graphs with vertex
-- labels and 'addLabeledVertex'/'addVertex'.  This requirement is enforced
-- in the type system so that labels cannot become out-of-sync with the
-- structure of the graph.  The adapters each work with any type of underlying
-- graph.
module Data.Graph.Haggle (
  -- * Basic Types
  Vertex,
  Edge,
  edgeSource,
  edgeDest,
  -- * Mutable Graphs
  MGraph(..),
  MAddEdge(..),
  MAddVertex(..),
  MRemovable(..),
  MBidirectional(..),
  MLabeledEdge(..),
  MLabeledVertex(..),
  -- * Immutable Graphs
  Graph(..),
  Bidirectional(..),
  HasEdgeLabel(..),
  HasVertexLabel(..)
  ) where

import Control.Monad ( forM )
import Control.Monad.Primitive
import Data.Graph.Haggle.Internal.Basic

-- | The interface supported by a mutable graph.
class MGraph (g :: (* -> *) -> *) where
  -- | The type generated by 'freeze'ing a mutable graph
  type ImmutableGraph g :: *

  -- | List all of the vertices in the graph.
  getVertices :: (PrimMonad m) => g m -> m [Vertex]

  -- | List the successors for the given 'Vertex'.
  getSuccessors :: (PrimMonad m) => g m -> Vertex -> m [Vertex]

  -- | Get all of the 'Edge's with the given 'Vertex' as their source.
  getOutEdges :: (PrimMonad m) => g m -> Vertex -> m [Edge]

  -- | Return the number of vertices in the graph
  countVertices :: (PrimMonad m) => g m -> m Int

  -- | Return the number of edges in the graph
  countEdges :: (PrimMonad m) => g m -> m Int

  -- | Edge existence test; this has a default implementation,
  -- but can be overridden if an implementation can support a
  -- better-than-linear version.
  checkEdgeExists :: (PrimMonad m) => g m -> Vertex -> Vertex -> m Bool
  checkEdgeExists g src dst = do
    succs <- getSuccessors g src
    return $ any (==dst) succs

  -- | Freeze the mutable graph into an immutable graph.
  freeze :: (PrimMonad m) => g m -> m (ImmutableGraph g)

class (MGraph g) => MAddVertex (g :: (* -> *) -> *) where
  -- | Add a new 'Vertex' to the graph, returning its handle.
  addVertex :: (PrimMonad m) => g m -> m Vertex

class (MGraph g) => MAddEdge (g :: (* -> *) -> *) where
  -- | Add a new 'Edge' to the graph from @src@ to @dst@.  If either
  -- the source or destination is not in the graph, returns Nothing.
  -- Otherwise, the 'Edge' reference is returned.
  addEdge :: (PrimMonad m) => g m -> Vertex -> Vertex -> m (Maybe Edge)

class (MGraph g) => MLabeledEdge (g :: (* -> *) -> *) where
  type MEdgeLabel g
  getEdgeLabel :: (PrimMonad m) => g m -> Edge -> m (Maybe (MEdgeLabel g))
  getEdgeLabel g e = do
    nEs <- countEdges g
    case edgeId e >= nEs of
      True -> return Nothing
      False -> unsafeGetEdgeLabel g e
  unsafeGetEdgeLabel :: (PrimMonad m) => g m -> Edge -> m (MEdgeLabel g)
  unsafeGetEdgeLabel g e = do
    Just l <- getEdgeLabel g e
    return l
  addLabeledEdge :: (PrimMonad m) => g m -> Vertex -> Vertex -> MEdgeLabel g -> m (Maybe Edge)

class (MGraph g) => MLabeledVertex (g :: (* -> *) -> *) where
  type MVertexLabel g
  getVertexLabel :: (PrimMonad m) => g m -> Vertex -> m (Maybe (MVertexLabel g))
  addLabeledVertex :: (PrimMonad m) => g m -> MVertexLabel g -> m Vertex
  getLabeledVertices :: (PrimMonad m) => g m -> m [(Vertex, MVertexLabel g)]
  getLabeledVertices g = do
    vs <- getVertices g
    forM vs $ \v -> do
      Just l <- getVertexLabel g v
      return (v, l)

-- | An interface for graphs that allow vertex and edge removal.  Note that
-- implementations are not required to reclaim storage from removed
-- vertices (just make them inaccessible).
class (MGraph g) => MRemovable g where
  removeVertex :: (PrimMonad m) => g m -> Vertex -> m ()
  removeEdgesBetween :: (PrimMonad m) => g m -> Vertex -> Vertex -> m ()
  removeEdge :: (PrimMonad m) => g m -> Edge -> m ()

-- | An interface for graphs that support looking at predecessor (incoming
-- edges) efficiently.
class (MGraph g) => MBidirectional g where
  getPredecessors :: (PrimMonad m) => g m -> Vertex -> m [Vertex]
  getInEdges :: (PrimMonad m) => g m -> Vertex -> m [Edge]

-- | The basic interface of immutable graphs.
class Graph g where
  type MutableGraph g :: (* -> *) -> *
  vertices :: g -> [Vertex]
  edges :: g -> [Edge]
  successors :: g -> Vertex -> [Vertex]
  outEdges :: g -> Vertex -> [Edge]
  edgeExists :: g -> Vertex -> Vertex -> Bool
  maxVertexId :: g -> Int
  isEmpty :: g -> Bool
  thaw :: (PrimMonad m) => g -> m (MutableGraph g m)

-- | The interface for immutable graphs with efficient access to
-- incoming edges.
class (Graph g) => Bidirectional g where
  predecessors :: g -> Vertex -> [Vertex]
  inEdges :: g -> Vertex -> [Edge]

-- | The interface for immutable graphs with labeled edges.
class (Graph g) => HasEdgeLabel g where
  type EdgeLabel g
  edgeLabel :: g -> Edge -> Maybe (EdgeLabel g)
  labeledEdges :: g -> [(Edge, EdgeLabel g)]

-- | The interface for immutable graphs with labeled vertices.
class (Graph g) => HasVertexLabel g where
  type VertexLabel g
  vertexLabel :: g -> Vertex -> Maybe (VertexLabel g)
  labeledVertices :: g -> [(Vertex, VertexLabel g)]


