/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["DM Sans", "sans-serif"],
        display: ["Playfair Display", "serif"],
        data: ["DM Sans", "sans-serif"],
      },
      colors: {
        pax: {
          canvas: "#FCF8F5",
          ink: "#1F2C3F",
          bronze: "#B39263",
          border: "#E5E0DA",
          muted: "#727b86",
          success: "#3F7655",
          warning: "#A96D27",
          danger: "#A64B47",
          white: "#FFFFFF",
        },
      },
      boxShadow: { pax: "0 4px 12px rgba(0,0,0,0.03)" },
      borderRadius: { xl: "0.75rem" },
    },
  },
  plugins: [],
};
