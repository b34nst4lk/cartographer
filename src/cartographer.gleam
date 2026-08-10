import app
import gleam/io

pub fn main() {
  case app.start("#app") {
    Ok(Nil) -> Nil
    Error(_) -> io.println("Cartographers: could not mount on #app")
  }
}
