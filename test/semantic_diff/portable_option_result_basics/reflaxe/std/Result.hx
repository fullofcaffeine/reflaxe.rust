package reflaxe.std;

enum Result<T, E> {
	Ok(value:T);
	Err(error:E);
}
