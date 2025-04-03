like [shadertoy](https://shadertoy.com)

a live (hot reloaded) testing environment for shaders with:
- convenient built in resources (pre defined functions, uniforms, sample able textures) for sdf, time, input
- useful ui options such as uniform and variable inspector (to view and manipulate)
- debugging information like compilation error logs
- file based interaction

<!-- ## defaults -->

## specials
specials are specific keywords prefixed with an "@" which effect the state of the running app
| special | action                        |
|---------|-------------------------------|
| pause   | pauses the application        |
| reset   | resets the time to 0          |
| tick (N)| tick the timer by N (signed)  |
| uniforms| print the value of uniforms   |
| inspect | prints the next line's value  |
| override| force the next line's value   |
|extern(s)| use an external symbol        |

e.g. a line (anywhere in the file) that reads `"@pause"` will pause the application
