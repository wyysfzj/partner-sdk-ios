# HSBC Partner SDK - Data Flow and Sequence Diagrams

## Data Flow Diagram

This diagram illustrates how data moves through the SDK components.

```mermaid
graph TD
    UserApp[User Application]
    SDK[HSBCPartnerSdk]
    Runtime[RuntimeEngine]
    Loader[ManifestLoader]
    Store[KeyStore]
    Machine[StateMachine]
    Bridge[Bridge]
    Container[HybridContainer]
    Client[ApiClient]
    WebView[WKWebView]
    Server[Remote Server]

    UserApp -->|Config| SDK
    UserApp -->|Start Params| SDK
    SDK -->|Delegates| Runtime
    Runtime -->|Load Manifest| Loader
    Loader -->|Verify Signature| Store
    Loader -->|Fetch| Server
    Runtime -->|Init| Machine
    Runtime -->|Init| Bridge
    Runtime -->|Init| Client
    Runtime -->|Present| Container
    
    Container -->|Hosts| WebView
    WebView -->|JS Events| Bridge
    Bridge -->|Events| Machine
    
    Machine -->|"Bindings (API Calls)"| Client
    Client -->|HTTP Requests| Server
    Client -->|Responses| Machine
    
    Machine -->|Emit Events| Bridge
    Bridge -->|JS Messages| WebView
    
    Machine -->|Transitions| Container
    Container -->|Load URL| WebView
```

## Sequence Diagram: Start Journey

This diagram shows the sequence of operations when starting a journey.

```mermaid
sequenceDiagram
    participant User as User App
    participant SDK as HSBCPartnerSdk
    participant Runtime as RuntimeEngine
    participant Loader as ManifestLoader
    participant Machine as StateMachine
    participant Container as HybridContainer
    participant WebView as WKWebView

    User->>SDK: initialize(config)
    User->>SDK: startJourney(params)
    SDK->>Runtime: start(config, params)
    
    activate Runtime
    Runtime->>Loader: load(journeyId)
    activate Loader
    Loader->>Loader: resolveManifestURL
    Loader->>Loader: fetchManifestData
    Loader->>Loader: verifySignature
    Loader->>Loader: validate
    Loader-->>Runtime: Manifest
    deactivate Loader
    
    Runtime->>Runtime: Resolve OpenAPI & Init ApiClient
    Runtime->>Runtime: Init Bridge & StateMachine
    
    Runtime->>Container: presentStepWebView(startStepUrl)
    activate Container
    Container->>WebView: Load URL
    Container-->>Runtime: UIViewController
    deactivate Container
    
    deactivate Runtime
```

## Sequence Diagram: Event Handling & Transition

This diagram shows how events from the web view are handled and lead to transitions.

```mermaid
sequenceDiagram
    participant WebView as WKWebView
    participant Bridge as Bridge
    participant Machine as StateMachine
    participant Client as ApiClient
    participant Server as Remote Server

    WebView->>Bridge: postMessage(event, payload)
    Bridge->>Machine: handleEvent(name, payload)
    
    activate Machine
    
    opt Bindings (API Calls)
        Machine->>Client: call(operationId, body)
        activate Client
        Client->>Server: HTTP Request
        Server-->>Client: HTTP Response
        Client-->>Machine: Result
        deactivate Client
        
        opt Emit Success/Error
            Machine->>Bridge: emit(eventName, result)
            Bridge->>WebView: dispatchEvent
        end
    end
    
    opt Transition
        Machine->>Machine: Evaluate Guard Expressions
        
        alt Transition to Next Step
            Machine->>Machine: move(to: nextStepId)
            Machine->>Bridge: emitStepEvents
            Machine->>WebView: Load Next URL (via Container)
        else Emit Event
            Machine->>Bridge: emit(eventName)
            Bridge->>WebView: dispatchEvent
        end
    end
    
    deactivate Machine
```
