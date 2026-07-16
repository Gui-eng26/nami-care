import Home from './pages/Home.jsx'

export default function App() {
  return (
    <div className="app">
      <header className="app-header">
        <h1>Nami Care</h1>
        <p>Gestão de medicação — casa de repouso</p>
      </header>
      <main className="app-main">
        <Home />
      </main>
    </div>
  )
}
