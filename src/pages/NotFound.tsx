import { Link } from "react-router-dom";

const NotFound = () => {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-background">
      <h1 className="text-4xl font-bold mb-4">404</h1>
      <p className="text-muted-foreground mb-4">Página não encontrada</p>
      <Link to="/" className="text-primary hover:underline">Voltar ao início</Link>
    </div>
  );
};

export default NotFound;
